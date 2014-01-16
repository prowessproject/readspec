readspec
========

ReadSpec application: making PBT easier to read for humans

Compiling & running
-------------------

Just clone the repository and execute

  make && ./run

You should then see an erlang shell in which you can try the following provided examples:

  readspec:suite(simple_eqc, fun simple_eqc:prop_simple/0, 20).

or

  readspec:suite(register_eqc, fun register_eqc:prop_register/0, 35).

This will create a suite.cucumberl file with a human-readable version of a test case example generated by QC from the corresponding test property/model.
