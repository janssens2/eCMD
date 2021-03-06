#!/usr/bin/env python
from fileinput import input
import re

# Read in a Python module generated by SWIG, extract all parameter names starting with o_
# or io_ and output a list of SWIG %apply statements to map them to output parameters.

o_names = set()
io_names = set()

def output(names, totype, fromtype):
    print("%%apply %s { %s };" % (totype, ", ".join(fromtype + name for name in sorted(names))))

for l in input():
    for word in re.split(r"\W+", l):
        if word.startswith("o_"):
            o_names.add(word)
        elif word.startswith("io_"):
            io_names.add(word)

output(o_names, "int &OUTPUT", "enum SWIGTYPE &")
output(o_names, "int &OUTPUT", "uint32_t &")
output(o_names, "int &OUTPUT", "uint64_t &")
output(o_names, "std::string &OUTPUT", "std::string &")
output(io_names, "int &INOUT", "enum SWIGTYPE &")
output(io_names, "int &INOUT", "uint32_t &")
output(io_names, "int &INOUT", "uint64_t &")
output(io_names, "std::string &INOUT", "std::string &")
