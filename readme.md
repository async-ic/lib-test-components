# lib test bench

is build to load test vectors from CSV files into your actsim or mixed signal simulation.
the library contains multiple source and check as well as dump helpers.

## The Concept

each test bench consists out of:

-   a DUT - device under test
-   multiple sources
-   multiple checker or dumpers
-   a controller - responcible for syncronising the release of test vectors

the execution order of the test bench is defined by the simulation steps and the order of the test vectors inside the simulation step

before the test bench proceeds to the next simulation step, it waits untill
- all sources have sent their test vectors
- all checkes have recieved all exspeced inputs
- the specified wait time for the simulation step has elapsed after the 2 conditions above have been satisfied.


the reason the test bench lib is splitt in components is that you can assable it to your need without writing it new for evert DUT

the reason to  load a control file is that you can run different test suits with the same test
bench by changing the set of csv files.

### Limitations for verilog 
Cadence AMS:

\- the test vector files can contain a maximum of 2.2M rows per simulation step, as they are cached for out of order checks
(`` `parameter integer MAX_CHECKS = 2200000; ``\`)

## The Control

a test bench includes one test bench controller that excecutes reset (verilog, prs), the
simulation step and the time out/end of the simulation (verilog)

Note: 
because the controller sets the time out in verilog set your simulation time in your simulator to way more than needed, the TB will end the simulation for you!

this unit is called **control**, it reads a file with the name `control.csv`.

the csv format is, one line per simulation step:
``` first line: <start step>, <end step> all other lines: <simulation step>, <time to wait for> ```

step 0 is the test initialisation - so the reset sequence - and is always
executed, it can not be used in the test bench.

verilog: wait statements are in ns (default for candence AMS) but can be changed in the simulatior options.

actsim: 0 means no wait, any positive number is waiting untill all signals have settled "cycle" (@TODO not supported yet)

the controll needs to be connected to sources, checkers and dumps, with both sim_step and done (excep dump)

before the test bench proceeds to the next simulation step, it waits until
- all sources have sent their test vectors
- all checkes have recieved all exspeced inputs
- the specified wait time for the simulation step has elapsed after the 2 conditions above have been satisfied.

## The Sources

the async sources present a word and initiate a handshake.

the csv format is: ``` <simulation_step>; <data to send>```

the file name is `source_<ID>.csv`. the ID is a variable specified during the buiding of the test bench, the numbering does not have to be consecutive.

for the normal sources excl. fifo/serial, the maximum vector width is assumed with 64 bits, as limited by actsim plugin system

the simultaion_step has to be >= 1

## The Checkers

the testers compare the in coming data to the vectors written in the csv
file.


there are different checkers:

- check in order: all vectors have to appear in the order of the file inside a simulation step
- check out of order: all vector can appear in random order, but each vector can only be used once.

the csv format is: ``` <simulation_step>; <data to send>```

the file name is `check_<ID>.csv`. the ID is a variable specified during the buiding of the test bench, the numbering does not have to be consecutive.

for the normal checkers excl. fifo/serial, the maximum vector width is assumed with 64 bits, as limited by actsim plugin system

## The Dumpers

the dumpers just write any incomming vector to file with format:

the csv format is: ``` <simulation_step>; <data to send>```

the file name is `dump_<ID>.csv`. the ID is a variable specified during the buiding of the test bench, the numbering does not have to be consecutive.

the maximum vector width is assumed with 64 bits, as limited by actsim plugin system

## CSV file stucture and location

currenty the files are read and searched in the excecution folder of actsim.

## running actsim 

the config file has to be included to load the test bench,

call `make install`

and after you can run ``` actsim -cnf=$ACT_HOME/tech/generic/actsim_test_bench_lib.conf <act file> <process> ```

## outstanding features:

 - [ ] sources with seperate address and data buses
 - [ ] verilog files in oa structure - what to do with symbols?
 - [ ] serial sources and checkers like scanchain/fifo/spi
 - [ ] actsim PRS support (incl reset) as ref=1
