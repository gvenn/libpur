%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%   Copyright 2016 Purvey, Inc.
%%
%%   Licensed under the Apache License, Version 2.0 (the "License");
%%   you may not use this file except in compliance with the License.
%%   You may obtain a copy of the License at
%%
%%       http://www.apache.org/licenses/LICENSE-2.0
%%
%%   Unless required by applicable law or agreed to in writing, software
%%   distributed under the License is distributed on an "AS IS" BASIS,
%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%   See the License for the specific language governing permissions and
%%   limitations under the License.
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @author: Garrison M. Venn
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-module(pur_tcp_modbus_tests).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_props.hrl").
-include_lib("pur_utls_pipes.hrl").
-include_lib("pur_tcp_modbus_server.hrl").

pur_tcp_modbus_test_server_test_() ->
    % Does not include failure tests
    MTS = pur_tcp_modbus_test_server,
    Registers = lists:seq(1, 10),
    RegVPairs = lists:zip(Registers, Registers),
    Args = [{registers, RegVPairs}],
    Server = test_server,
    MTS:spawn(link, {local, Server}, Args, []),
    BaseReg = 1,
    NumRegs = 10,
    PipeFun = 
        fun (_Context, _To, _Message) ->
            %?LogIt(pur_tcp_modbus_test_server_test_,
            %       "Received for To: ~p, with message: ~p, and "
            %           "context: ~n~p.~n", 
            %       [_To, _Message, _Context])
            ok
        end,
    [ServerPipeComp] = gen_server:call(Server, build_pipe_handler),
    PipeFunComp = #pipecomp{name = "PrintIt", 
                            pipe_name = ServerPipeComp#pipecomp.pipe_name,
                            type = function,
                            exec = PipeFun,
                            to = self()},
    TestPipe = [ServerPipeComp, PipeFunComp],
    pur_utls_pipes:send_to_next(
        {#response_id{request_id = 1,
                      trans_id = 1,
                      unit_id = 1,
                      funct_code = 16#03},
         {read_holding_registers, BaseReg, NumRegs}},
        1,
        TestPipe),
    T1 = gen_server:call(Server, {get_registers, BaseReg, NumRegs}),
    pur_utls_pipes:send_to_next(
        {#response_id{request_id = 1,
                      trans_id = 1,
                      unit_id = 1,
                      funct_code = 16#06},
         {write_single_register, BaseReg + 2, 1, [13]}},
        1,
        TestPipe),
    T2 = gen_server:call(Server, {get_registers, BaseReg, NumRegs}),
    pur_utls_pipes:send_to_next(
        {#response_id{request_id = 1,
                      trans_id = 1,
                      unit_id = 1,
                      funct_code = 16#10},
         {write_single_register, BaseReg + 3, 7, lists:seq(1,7)}},
        1,
        TestPipe),
    T3 = gen_server:call(Server, {get_registers, BaseReg, NumRegs}),
    pur_utls_pipes:send_to_next(
        {#response_id{request_id = 1,
                      trans_id = 1,
                      unit_id = 1,
                      funct_code = 16#03},
         {read_holding_registers, BaseReg + 5, NumRegs}},
        1,
        TestPipe),
    ?assert(ok =:= gen_server:stop(Server)),
    [begin
         %?LogIt(pur_tcp_modbus_test_server_test_, "T1 = ~p.", [T1]),
         ?_assert([1,2,3,4,5,6,7,8,9,10] =:= T1)
     end,
     begin
         %?LogIt(pur_tcp_modbus_test_server_test_, "T2 = ~p.", [T2]),
         ?_assert([1,2,13,4,5,6,7,8,9,10] =:= T2)
     end,
     begin
         %?LogIt(pur_tcp_modbus_test_server_test_, "T3 = ~p.", [T3]),
         ?_assert([1,2,13,1,2,3,4,5,6,7] =:= T3)
     end].

pur_tcp_modbus_iter_server_test_() ->
    %timer:sleep(10000),
    % Ports must be manually incremented since without sleeps socket bindings
    %    do not seem to be released or expired in time.
    Port = 9000,
    MTS = pur_tcp_modbus_test_server,
    Registers = lists:seq(1, 10),
    RegVPairs = lists:zip(Registers, Registers),
    Args = [{registers, RegVPairs}],
    Server = test_server,
    MTS:spawn(link, {local, Server}, Args, []),
    BaseReg = 1,
    NumRegs = 10,
    I1 = gen_server:call(Server, {get_registers, BaseReg, NumRegs}),
    AM = pur_utls_accept_server,
    AcceptServer = test_accept_server,
    AcceptArgs = [{port, Port}, 
                  {comm_module, pur_tcp_modbus_iter_server},
                  {pipe_endpoint, Server},
                  {pipe_build_term, build_pipe_handler}],
    AM:spawn(link, {local, AcceptServer}, AcceptArgs, []),
    I2 = gen_server:call(AcceptServer, start),
    ClientArgs = [{hostname, "127.0.0.1"}, {port, Port}],
    pur_tcp_modbus:spawn(link, {local, modbus_client}, ClientArgs, []),
    ?LogIt(pur_tcp_modbus_iter_server_test_, 
           "About to connect to port: ~p.",
           [Port]),
    I3 = gen_server:call(modbus_client, connect),
    T1 = gen_server:call(modbus_client, {read_holding_registers, 1, 1}),
    T2 = gen_server:call(modbus_client, {read_holding_registers, 1, 10}),
    T3 = gen_server:call(modbus_client, {read_input_registers, 1, 10}),
    gen_server:call(modbus_client, {write_single_register, 3, 13}),
    T4 = gen_server:call(modbus_client, {read_input_registers, 1, 10}),
    gen_server:call(modbus_client, 
                    {write_multiple_registers, 4, 7, lists:seq(1,7)}),
    T5 = gen_server:call(modbus_client, {read_input_registers, 1, 10}),
    F1 = gen_server:call(modbus_client, {read_holding_registers, 11, 1}),
    F2 = gen_server:call(modbus_client, {read_holding_registers, 1, 11}),
    F3 = gen_server:call(modbus_client, {read_input_registers, 1, 11}),
    F4 = gen_server:call(modbus_client, {write_single_register, 11, 13}),
    F5 = gen_server:call(modbus_client, 
                         {write_multiple_registers, 4, 8, lists:seq(1,7)}),
    F6 = gen_server:call(modbus_client, 
                         {write_multiple_registers, 4, 8, lists:seq(1,8)}),
    S1 = gen_server:stop(modbus_client),
    S2 = gen_server:stop(AcceptServer),
    S3 = gen_server:stop(Server),
    %timer:sleep(5000),
    [begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "I1 = ~p.", [I1]),
         ?_assert([1,2,3,4,5,6,7,8,9,10] =:= I1)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "I2 = ~p.", [I2]),
         ?_assert(ok =:= I2)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "I3 = ~p.", [I3]),
         ?_assert(ok =:= I3)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "T1 = ~p.", [T1]),
         ?_assert({ok, [1]} =:= T1)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "T2 = ~p.", [T2]),
         ?_assert({ok, [1,2,3,4,5,6,7,8,9,10]} =:= T2)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "T3 = ~p.", [T3]),
         ?_assert({ok, [1,2,3,4,5,6,7,8,9,10]} =:= T3)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "T4 = ~p.", [T4]),
         ?_assert({ok, [1,2,13,4,5,6,7,8,9,10]} =:= T4)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "T5 = ~p.", [T5]),
         ?_assert({ok, [1,2,13,1,2,3,4,5,6,7]} =:= T5)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "F1 = ~p.", [F1]),
         ?_assert({exception, illegal_data_address} =:= F1)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "F2 = ~p.", [F2]),
         ?_assert({exception, illegal_data_address} =:= F2)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "F3 = ~p.", [F3]),
         ?_assert({exception, illegal_data_address} =:= F3)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "F4 = ~p.", [F4]),
         ?_assert({exception, illegal_data_address} =:= F4)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "F5 = ~p.", [F5]),
         ?_assert({error, bad_request} =:= F5)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "F6 = ~p.", [F6]),
         ?_assert({exception, illegal_data_address} =:= F6)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "S1 = ~p.", [S1]),
         ?_assert(ok =:= S1)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "S2 = ~p.", [S2]),
         ?_assert(ok =:= S2)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "S3 = ~p.", [S3]),
         ?_assert(ok =:= S3)
     end].

pur_tcp_modbus_server_test_() ->
    %timer:sleep(10000),
    % Ports must be manually incremented since without sleeps socket bindings
    %    do not seem to be released or expired in time.
    Port = 9000,
    MTS = pur_tcp_modbus_test_server,
    Registers = lists:seq(1, 10),
    RegVPairs = lists:zip(Registers, Registers),
    Args = [{registers, RegVPairs}],
    Server = test_server,
    MTS:spawn(link, {local, Server}, Args, []),
    BaseReg = 1,
    NumRegs = 10,
    I1 = gen_server:call(Server, {get_registers, BaseReg, NumRegs}),
    AM = pur_utls_accept_server,
    AcceptServer = test_accept_server,
    AcceptArgs = [{port, Port}, 
                  {comm_module, pur_tcp_modbus_server},
                  {pipe_endpoint, Server},
                  {pipe_build_term, build_pipe_handler}],
    AM:spawn(link, {local, AcceptServer}, AcceptArgs, []),
    I2 = gen_server:call(AcceptServer, start),
    ClientArgs = [{hostname, "127.0.0.1"}, {port, Port}],
    pur_tcp_modbus:spawn(link, {local, modbus_client}, ClientArgs, []),
    ?LogIt(pur_tcp_modbus_server_test_, 
           "About to connect to port: ~p.",
           [Port]),
    I3 = gen_server:call(modbus_client, connect),
    T1 = gen_server:call(modbus_client, {read_holding_registers, 1, 1}),
    T2 = gen_server:call(modbus_client, {read_holding_registers, 1, 10}),
    T3 = gen_server:call(modbus_client, {read_input_registers, 1, 10}),
    gen_server:call(modbus_client, {write_single_register, 3, 13}),
    T4 = gen_server:call(modbus_client, {read_input_registers, 1, 10}),
    gen_server:call(modbus_client, 
                    {write_multiple_registers, 4, 7, lists:seq(1,7)}),
    T5 = gen_server:call(modbus_client, {read_input_registers, 1, 10}),
    F1 = gen_server:call(modbus_client, {read_holding_registers, 11, 1}),
    F2 = gen_server:call(modbus_client, {read_holding_registers, 1, 11}),
    F3 = gen_server:call(modbus_client, {read_input_registers, 1, 11}),
    F4 = gen_server:call(modbus_client, {write_single_register, 11, 13}),
    F5 = gen_server:call(modbus_client, 
                         {write_multiple_registers, 4, 8, lists:seq(1,7)}),
    F6 = gen_server:call(modbus_client, 
                         {write_multiple_registers, 4, 8, lists:seq(1,8)}),
    S1 = gen_server:stop(modbus_client),
    S2 = gen_server:stop(AcceptServer),
    S3 = gen_server:stop(Server),
    %timer:sleep(5000),
    [begin
         %?LogIt(pur_tcp_modbus_server_test_, "I1 = ~p.", [I1]),
         ?_assert([1,2,3,4,5,6,7,8,9,10] =:= I1)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "I2 = ~p.", [I2]),
         ?_assert(ok =:= I2)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "I3 = ~p.", [I3]),
         ?_assert(ok =:= I3)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "T1 = ~p.", [T1]),
         ?_assert({ok, [1]} =:= T1)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "T2 = ~p.", [T2]),
         ?_assert({ok, [1,2,3,4,5,6,7,8,9,10]} =:= T2)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "T3 = ~p.", [T3]),
         ?_assert({ok, [1,2,3,4,5,6,7,8,9,10]} =:= T3)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "T4 = ~p.", [T4]),
         ?_assert({ok, [1,2,13,4,5,6,7,8,9,10]} =:= T4)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "T5 = ~p.", [T5]),
         ?_assert({ok, [1,2,13,1,2,3,4,5,6,7]} =:= T5)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "F1 = ~p.", [F1]),
         ?_assert({exception, illegal_data_address} =:= F1)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "F2 = ~p.", [F2]),
         ?_assert({exception, illegal_data_address} =:= F2)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "F3 = ~p.", [F3]),
         ?_assert({exception, illegal_data_address} =:= F3)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "F4 = ~p.", [F4]),
         ?_assert({exception, illegal_data_address} =:= F4)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "F5 = ~p.", [F5]),
         ?_assert({error, bad_request} =:= F5)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "F6 = ~p.", [F6]),
         ?_assert({exception, illegal_data_address} =:= F6)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "S1 = ~p.", [S1]),
         ?_assert(ok =:= S1)
     end,
     begin
         %?LogIt(pur_tcp_modbus_server_test_, "S2 = ~p.", [S2]),
         ?_assert(ok =:= S2)
     end,
     begin
         %?LogIt(pur_tcp_modbus_iter_server_test_, "S3 = ~p.", [S3]),
         ?_assert(ok =:= S3)
     end].

-endif.

