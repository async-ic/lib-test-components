#!/usr/bin/env python
# coding: utf-8

# Copyright 2025 Ole Richter - Yale University
# Copyright 2022 Hugh Greatorex - University of Groningen
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation; either version 2
#  of the License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor,
#  Boston, MA  02110-1301, USA.
 

import re
import os
import glob
import shutil

import sys

# Check if file path is provided as argument
if len(sys.argv) != 2:
    print("Usage: create_oa_from_verilog.py <netlist_file_path>")
    sys.exit(1)

# Get file path from command line argument
path = sys.argv[1]

path = glob.glob(path)[0]

# Check if file exists
if not os.path.exists(path):
    print(f"Error: File '{path}' not found")
    sys.exit(1)

with open(path) as f:
    veri = f.read()

'''Pick out modules'''

modules = re.findall(r'(?<=\n)(module ([a-z_0-9]*)[\([\w]*?[\s\S]*?endmodule)', veri)


tag = '-- Master.tag File, Rev:1.0 \nverilog.v'

for i in modules:
    
    path = '/oa/' + i[1] + '/netlist'
    
    if glob.glob(path):
        shutil.rmtree(path)
    
    os.makedirs(path)
    
    with open(path + '/verilog.v', 'w') as w:
        w.write(i[0])
    with open(path + '/master.tag', 'w') as w:
        w.write(tag)
