Build Status:  [![Build Status](https://travis-ci.org/bkearns/libpur.svg?branch=master)](https://travis-ci.org/bkearns/libpur)
libpur
=====

An experimental OTP library including support for a pipe like wiring 
semantic, xdr, modbus, other miscellaneous features.

Build
-----

    $ rebar3 compile

Unit Test
---------

    $ rebar3 eunit

Using with repl
---------

    $ rebar3 shell

Caveats
-------

1. No Specs
2. No Doc
3. Code test coverage not complete
4. XDR modules have not yet been tested against native (C, other), libraries
5. Some test modules seem to execute twice, which is believed to be due to incorrect use of ...test_ functions. Have not had time to investigate this.
6. Test function release of socket bindings seem to sometimes fail. Re-execute rebar3 eunit after possibly waiting first, if this happens. Although this is not seen anymore on author's development system, the issue may crop up in other development environments/platforms. Again have not investigated the cause.
7. Modbus over TCP functionality, not fully supported, and has not been continually tested against external systems.
8. Pipe semantic not fully flushed out.
9. Logging system does not provide 3rd party developers with mechanism to control/overide logging mechanism.
10. rebar3 eunit produces logs of socket errors due to test server side components being shutdown after each associated test. Ignore these. Only test failures are indicative of issues.
11. Tested on OS X with erlang 18.1, and 17.5; not sure about the full implications of using maps with 17.x.


