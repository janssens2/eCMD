//IBM_PROLOG_BEGIN_TAG
/* 
 * Copyright 2003,2020 IBM International Business Machines Corp.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * 	http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
//IBM_PROLOG_END_TAG

/**
 * @file ServerXDMAInstruction.C
 * @brief Provides a class for XDMA access on the bmc server
 *
*/

#include <ServerXDMAInstruction.H>
#include <OutputLite.H>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <sstream>
#include <iomanip>
#include <cstring>

#include <sys/mman.h>
#include <sys/ioctl.h>
#include <linux/types.h> // needed for __u64, etc types
#include <delay.h>

extern bool global_server_debug;

// data/structures/defines from aspeed-xdma.h
// necessary due to build env not having file in packages yet
#define __ASPEED_XDMA_IOCTL_MAGIC       0xb7
#define ASPEED_XDMA_IOCTL_RESET         _IO(__ASPEED_XDMA_IOCTL_MAGIC, 0)

enum aspeed_xdma_direction {
        ASPEED_XDMA_DIRECTION_DOWNSTREAM = 0,
        ASPEED_XDMA_DIRECTION_UPSTREAM,
};

struct aspeed_xdma_op {
        __u64 host_addr;
        __u32 len;
        __u32 direction;
};

uint32_t ServerXDMAInstruction::xdma_open(Handle ** handle, InstructionStatus & o_status)
{
    uint32_t l_rc = 0;
    std::ostringstream errstr;
    std::ostringstream device;

    if ( *handle != NULL )
        return l_rc;

    /* Open the device */

    device << "/dev/aspeed-xdma";

    errno = 0;

    if ( flags & INSTRUCTION_FLAG_SERVER_DEBUG )
    {
        errstr << "SERVER_DEBUG : open(" << device.str() << ", O_RDWR" << std::endl;
        o_status.errorMessage.append(errstr.str());
        errstr.str(""); errstr.clear();
    }

#ifdef TESTING
    TEST_PRINT("*handle = open(%s, O_RDWR)\n", device.str().c_str());
    *handle = (Handle *) 55;
#else
    *handle = (Handle *) open(device.str().c_str(), O_RDWR);
#endif

    if ( flags & INSTRUCTION_FLAG_SERVER_DEBUG )
    {
        errstr << "SERVER_DEBUG : open() *handle = " << *handle << ::std::endl;
        o_status.errorMessage.append(errstr.str());
        errstr.str(""); errstr.clear();
    }

    if ( *handle == NULL || (*handle != NULL && (int32_t)*handle < 0) )
    {
        errstr << "ServerXDMAInstruction::xdma_open Problem opening xdma device " << device.str() << " errno " << errno << std::endl;
        o_status.errorMessage.append(errstr.str());
        errstr.str(""); errstr.clear();
        l_rc = o_status.rc = SERVER_XDMA_OPEN_FAIL;
        return l_rc;
    }

    return l_rc;
}

void ServerXDMAInstruction::xdma_ffdc(Handle ** handle, InstructionStatus & o_status)
{
    uint32_t l_rc = xdma_close(*handle);
    *handle = NULL;
    if ( l_rc ) o_status.rc = SERVER_XDMA_CLOSE_FAIL;
}

void ServerXDMAInstruction::xdma_reset(Handle * handle, InstructionStatus & o_status)
{
    uint32_t l_rc = 0;
    std::ostringstream errstr;

    errno = 0;

    if ( flags & INSTRUCTION_FLAG_SERVER_DEBUG )
    {
        errstr << "SERVER_DEBUG : ioctl(fd, ASPEED_XDMA_IOCTL_RESET" << std::endl;
        o_status.errorMessage.append(errstr.str());
        errstr.str(""); errstr.clear();
    }

#ifdef TESTING
    TEST_PRINT("ioctl(%d, ASPEED_XDMA_IOCTL_RESET)\n", (int)handle);
#else
    l_rc = ioctl((int) handle, ASPEED_XDMA_IOCTL_RESET);
#endif

    if ( flags & INSTRUCTION_FLAG_SERVER_DEBUG )
    {
        errstr << "SERVER_DEBUG : ioctl() *handle = " << (int)handle << ::std::endl;
        o_status.errorMessage.append(errstr.str());
        errstr.str(""); errstr.clear();
    }

    if ( l_rc < 0 )
    {
        errstr << "ServerXDMAInstruction::xdma_reset error during ioctl rc (" << l_rc << ") errno " << errno << std::endl;
        o_status.errorMessage.append(errstr.str());
        errstr.str(""); errstr.clear();
        l_rc = o_status.rc = SERVER_XDMA_OPEN_FAIL;
    }

}

uint32_t ServerXDMAInstruction::xdma_close(Handle * handle)
{
    uint32_t l_rc = 0;
#ifdef TESTING
    TEST_PRINT("close()\n");
#else
    close((int) handle);
#endif
    return l_rc;
}

ssize_t ServerXDMAInstruction::xdma_command(Handle * i_handle, ecmdDataBufferBase & o_data, InstructionStatus & o_status)
{
    ssize_t l_rc = 0;
    int l_intrc = 0;
    uint32_t l_uintrc = 0;
    uint32_t l_len = 0;
    std::ostringstream errstr;
    uint8_t * l_buffer = NULL;
    uint8_t * l_mmap = NULL;

    struct aspeed_xdma_op l_xdma_op;
    struct pollfd l_pollfd;

    // data is what we would write if readLength == 0, o_data is populated with readLength bytes for the read

    do
    {
        if ( (data == NULL) && (readLength == 0) )
        {
            errstr << "ServerXDMAInstruction::xdma_command no data specified to read / write (input data is null) and readLength is 0" << std::endl;
            o_status.errorMessage.append(errstr.str());
            errstr.str(""); errstr.clear();
            l_rc = SERVER_XDMA_COMMAND_FAIL;
            break;
        }

        uint32_t l_tmpLen = 0;

        if ( readLength )
            l_tmpLen = readLength;
        else
            l_tmpLen = data->getByteLength();

        // determine alignment
        const int l_pgSize = getpagesize();
        uint32_t l_numPages = l_tmpLen / l_pgSize;
        l_len = l_numPages * l_pgSize;
        if ( l_tmpLen > l_len ) l_len += l_pgSize; 

        if ( readLength )
        {
            // setup the o_data buffer to the appropriate size
            // o_data will be readLength size since l_len could be larger
            // only readLength size will be copied into o_data at end of op
            o_data.setByteLength( readLength );
            l_buffer = new uint8_t[l_len];
            if ( l_buffer == 0 )
            {
                errstr << "ServerXDMAInstruction::xdma_command could not allocate buffer" << std::endl;
                o_status.errorMessage.append(errstr.str());
                errstr.str(""); errstr.clear();
                l_rc = -1;
                break;
            }
        }
        else
        {
            // setup the data buffer
            l_buffer = new uint8_t[l_len];
            if ( l_buffer == 0 )
            {
                errstr << "ServerXDMAInstruction::xdma_command could not allocate buffer" << std::endl;
                o_status.errorMessage.append(errstr.str());
                errstr.str(""); errstr.clear();
                l_rc = -1;
                break;
            }

            //  and copy to a uint8_t* array
            l_uintrc = data->extract( l_buffer, 0, data->getBitLength() );
            if ( l_uintrc )
            {
                errstr << "ServerXDMAInstruction::xdma_command error during extract: " << std::hex << std::setfill('0') << std::setw(8) << l_uintrc << std::endl;
                o_status.errorMessage.append(errstr.str());
                errstr.str(""); errstr.clear();
                l_rc = -1;
                break;
            }
        }

        l_mmap = static_cast<uint8_t*>(mmap(NULL, l_len, (readLength ? PROT_READ : PROT_WRITE), MAP_SHARED, (int)i_handle, 0));
        if ( l_mmap == 0 )
        {
            errstr << "ServerXDMAInstruction::xdma_command could not allocate mmap errno " << errno << std::endl;
            o_status.errorMessage.append(errstr.str());
            errstr.str(""); errstr.clear();
            l_rc = -1;
            break;
        }

        if ( !readLength )
        {
            // copy the input data buffer to write to the mmap
            memcpy(l_mmap, l_buffer, l_len);
        }

        errno = 0;

        // setup the xdma command
        l_xdma_op.direction = (readLength ? ASPEED_XDMA_DIRECTION_DOWNSTREAM : ASPEED_XDMA_DIRECTION_UPSTREAM);
        l_xdma_op.host_addr = address;
        l_xdma_op.len = l_len;

        if ( flags & INSTRUCTION_FLAG_SERVER_DEBUG )
        {
            errstr << "SERVER_DEBUG : write(*handle = " << (int)i_handle << ", addr=" << std::hex << std::setfill('0') << std::setw(8) << l_xdma_op.host_addr;
            errstr << " len=" << std::dec << l_xdma_op.len << " direction=" << l_xdma_op.direction << ", size=" << sizeof(l_xdma_op) << ")" << ::std::endl;
            o_status.errorMessage.append(errstr.str());
            errstr.str(""); errstr.clear();
        }

#ifdef TESTING
        TEST_PRINT("write(%d, addr=%08X len=%d upstream=%d, size(%d))\n", (int)i_handle, l_xdma_op.host_addr, l_xdma_op.len, l_xdma_op.upstream, sizeof(l_xdma_op));
        l_rc = 0;
#else
        l_rc = write( (int)i_handle, &l_xdma_op, sizeof(l_xdma_op) );
#endif
        if ( l_rc < 0 )
        {
            errstr << "ServerXDMAInstruction::xdma_command error during xdma write() operation rc " << l_rc << ", errno " << errno << std::endl;
            o_status.errorMessage.append(errstr.str());
            errstr.str(""); errstr.clear();
            l_rc = o_status.rc = SERVER_XDMA_COMMAND_FAIL;
            break;
        }

        if ( flags & INSTRUCTION_FLAG_SERVER_DEBUG )
        {
            errstr << "SERVER_DEBUG : write() returned rc=" << l_rc << " errno=" << errno << ::std::endl;
            o_status.errorMessage.append(errstr.str());
            errstr.str(""); errstr.clear();
        }

        // polling stuff
        errno = 0;
        l_pollfd.fd = (int)i_handle;
        l_pollfd.events = POLLIN;
        l_intrc = poll( &l_pollfd, 1, -1 );
        if ( l_intrc < 0 )
        {
            errstr << "ServerXDMAInstruction::xdma_command error during xdma poll() operation rc " << l_intrc << ", errno " << errno << std::endl;
            o_status.errorMessage.append(errstr.str());
            errstr.str(""); errstr.clear();
            l_rc = o_status.rc = SERVER_XDMA_COMMAND_FAIL;
            break;
        }

        if ( readLength )
        {
            // copy the buffer to o_data
            l_uintrc = o_data.insert( l_buffer, 0, readLength );
            if ( l_uintrc )
            {
                errstr << "ServerXDMAInstruction::xdma_command error during insert: " << std::hex << std::setfill('0') << std::setw(8) << l_uintrc << std::endl;
                o_status.errorMessage.append(errstr.str());
                errstr.str(""); errstr.clear();
                l_rc = -1;
                break;
            }

            errno = 0;
            l_intrc = msync( l_buffer, l_len, MS_SYNC );
            if ( !l_intrc )
            {
                errstr << "ServerXDMAInstruction::xdma_command error during msync: rc:" << l_intrc << ", errno:" << errno << std::endl;
                o_status.errorMessage.append(errstr.str());
                errstr.str(""); errstr.clear();
                l_rc = -1;
                break;
            }
        }

        l_rc = readLength;

    } while (0);

    // cleanup memory allocations
    if ( l_mmap )
    {
        l_intrc = munmap( l_mmap, l_len );
        if ( !l_intrc )
        {
            errstr << "ServerXDMAInstruction::xdma_command error during munmap: rc:" << l_intrc << ", errno:" << errno << std::endl;
            o_status.errorMessage.append(errstr.str());
            errstr.str(""); errstr.clear();
            l_rc = -1;
        }
    }

    if ( l_buffer )
        delete [] l_buffer;

    return l_rc;
}
