/* IBM_PROLOG_BEGIN_TAG                                                   */
/* 
 * Copyright 2017 IBM International Business Machines Corp.
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
/* IBM_PROLOG_END_TAG                                                     */
/// @file vpd_access.H
///
/// @brief VPD access functions that needs to be specialized for
/// platform implementation.
///

#ifndef __VPDACCESS_H_
#define __VPDACCESS_H_

#include <target.H>
#include <return_code.H>
#include <plat_vpd_access.H>
#include <fapi2_vpd_access.H>
namespace fapi2
{

    template<TargetType T, MulticastType M, typename V>
    inline ReturnCode getVPD(const Target<T, M, V>& i_target,
                             VPDInfo<T>& io_vpd_info,
                             uint8_t* o_blob)
    {
        return platGetVPD( i_target, io_vpd_info, o_blob );
    }

};

#endif // _FAPI2_VPDACCESS_H_
