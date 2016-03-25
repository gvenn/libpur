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

-module(pur_tcp_modbus).

-behavior(pur_utls_pipe_server).

% Synchronous implementation

-export([spawn/4, spawn/3,
         handle_call/3, handle_cast/2, handle_info/2, handle_pipe/2,
         terminate/2, code_change/3,
         init/1]).

-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_props.hrl").
-include_lib("pur_utls_pipes.hrl").
-include_lib("pur_tcp_modbus.hrl").

%%----------------------------------------------------------------------------
%% Records
%%----------------------------------------------------------------------------

-define(DefaultConnectTimeout, 100).
-define(DefaultSendTimeout, 100).
-define(DefaultConnectOptions, 
        [binary, {packet, raw}, {active, false}, {nodelay, true}]).

% Send logic WILL re-attempt connection establishment on failure
-define(DefaultMaxResendCount, 5).
% Recv logic WILL NOT re-attempt connection establishment on failure
-define(DefaultMaxRerecvCount, 3).
-define(DefaultMaxReconnectCount, 10).

-define(DefaultUnitId, 16#FF).
-define(DefaultRecvTimeout, 100).
-define(HeaderReceiveSize, 6).

% Requests
-define(ReadHoldingRegisters, 16#03).
-define(ReadInputRegisters, 16#04).
-define(WriteSingleRegister, 16#06).
-define(WriteMultipleRegisters, 16#10).

% One server instance per hostname/port combination with synchronous behaviour

-record(request_id, {trans_id, unit_id}).

-record(state, {hostname,
                port,
                socket,
                next_trans_id = 1,
                unit_id,
                % Not the overall send timeout because of retrys
                send_timeout,
                % Not the overall recv timeout because of retrys
                recv_timeout,
                connect_options,
                max_resend_count,
                max_rerecv_count,
                max_reconnect_count}).

%%----------------------------------------------------------------------------
%% "Init" Behavior
%%----------------------------------------------------------------------------

init(Props) -> 
    InitFunctions =
        [fun (_NProps, _Context, State = #state{send_timeout = Timeout,
                                                connect_options = Options}) ->
            NOptions = 
                lists:filter(
                    fun 
                        ({send_timeout_close, _}) -> false;
                        ({send_timeout, _}) -> false;
                        (_EProp) -> true
                    end,
                    Options),
            {true, 
             State#state{connect_options = [{send_timeout, Timeout}|NOptions]}}
        end],
    pur_utls_server:auto_init(
        Props,
        [#propdesc{name = "hostname", 
                   index = #state.hostname,
                   ret_type = list,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "port",
                   index = #state.port,
                   ret_type = integer,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "unit_id",
                   index = #state.unit_id,
                   ret_type = integer,
                   directive = default,
                   dirvalue = ?DefaultUnitId},
         #propdesc{name = "send_timeout",
                   index = #state.send_timeout,
                   ret_type = integer,
                   directive = default,
                   dirvalue = ?DefaultSendTimeout},
         #propdesc{name = "recv_timeout",
                   index = #state.recv_timeout,
                   ret_type = integer,
                   directive = default,
                   dirvalue = ?DefaultRecvTimeout},
         #propdesc{name = "connect_options",
                   index = #state.connect_options,
                   ret_type = list,
                   directive = default,
                   dirvalue = ?DefaultConnectOptions},
         #propdesc{name = "max_resend_count",
                   index = #state.max_resend_count,
                   ret_type = integer,
                   directive = default,
                   dirvalue = ?DefaultMaxResendCount},
         #propdesc{name = "max_rerecv_count",
                   index = #state.max_rerecv_count,
                   ret_type = integer,
                   directive = default,
                   dirvalue = ?DefaultMaxRerecvCount},
         #propdesc{name = "max_reconnect_count",
                   index = #state.max_reconnect_count,
                   ret_type = integer,
                   directive = default,
                   dirvalue = ?DefaultMaxReconnectCount}],
        InitFunctions,
        ok,
        #state{}).

terminate(Reason, State) ->
    CState = close(State),
    case Reason of
        normal -> ok;
        shutdown -> ok;
        {shutdown, _} -> ok;
        Reason -> ?LogIt(terminate,
                         "Terminated for reason: ~n~p, ~nwith state:~n~p.",
                         [Reason, CState])
    end.

code_change(_, State, _) -> 
    {ok, State}.

%%----------------------------------------------------------------------------
%% Genserver Exported Behavior
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% handle_call
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% connect
%%----------------------------------------------------------------------------

% May want to add options both here and maybe for init
handle_call(connect, 
            _From, 
            State = #state{socket = undefined}) ->
    {Reply, NState} =
        case reconnect(State) of
            {false, CState} ->
                {{error, connection_failure}, CState};
            {true, CState} ->
                {ok, CState}
        end,
    {reply, Reply, NState};

handle_call(connect, _From, State) ->
    {reply, true, State};

%%----------------------------------------------------------------------------
%% get_unit_id
%%---------------------------------------------------------------------------

handle_call(get_unit_id, _From, State = #state{unit_id = UnitId}) ->
    {reply, UnitId, State};

%%----------------------------------------------------------------------------
%% set_unit_id
%%---------------------------------------------------------------------------

handle_call({set_unit_id, ReqUnitId}, _From, State) when
        is_integer(ReqUnitId) ->
    <<UnitId>> = <<ReqUnitId:8>>,
    {reply, ok, State#state{unit_id = UnitId}};

%%----------------------------------------------------------------------------
%% read_holding_registers
%%---------------------------------------------------------------------------

handle_call({read_holding_registers, StartAddress, NumberOfRegisters},
            _From,
            State = #state{unit_id = UnitId}) ->
    {Result, NState} = 
        read_holding_registers(StartAddress, NumberOfRegisters, UnitId, State),
    {reply, Result, NState};

%%----------------------------------------------------------------------------
%% read_input_registers
%%---------------------------------------------------------------------------

handle_call({read_input_registers, StartAddress, NumberOfRegisters},
            _From,
            State = #state{unit_id = UnitId}) ->
    {Result, NState} = 
        read_input_registers(StartAddress, NumberOfRegisters, UnitId, State),
    {reply, Result, NState};

%%----------------------------------------------------------------------------
%% write_single_register
%%---------------------------------------------------------------------------

handle_call({write_single_register, RegisterAddr, Value},
            _From,
            State = #state{unit_id = UnitId}) ->
    {Result, NState} = 
        write_single_register(RegisterAddr, Value, UnitId, State),
    {reply, Result, NState};

%%----------------------------------------------------------------------------
%% write_multiple_registers
%%---------------------------------------------------------------------------

handle_call({write_multiple_registers, 
             StartAddress, 
             NumberOfRegisters, 
             Values},
            _From,
            State = #state{unit_id = UnitId}) ->
    {Result, NState} = 
        write_multiple_registers(StartAddress, 
                                 NumberOfRegisters, 
                                 Values, 
                                 UnitId,
                                 State),
    {reply, Result, NState};

%%----------------------------------------------------------------------------
%% close
%%----------------------------------------------------------------------------

handle_call(close, _From, State) ->
    {reply, ok, close(State)};

%%----------------------------------------------------------------------------
%% Unknown call expression
%%----------------------------------------------------------------------------

handle_call(Expr, _From, State) ->
    ?LogIt({handle_call, unknown}, "Unknown expr: ~n~p. ~nIgnoring", [Expr]),
    {reply, ok, State}.

%%----------------------------------------------------------------------------
%% handle_cast
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% set_unit_id
%%---------------------------------------------------------------------------

handle_cast({set_unit_id, ReqUnitId}, State) ->
    <<UnitId>> = <<ReqUnitId:8>>,
    {noreply, State#state{unit_id = UnitId}};

%%----------------------------------------------------------------------------
%% read_holding_registers
%%----------------------------------------------------------------------------

handle_cast({{read_holding_registers, StartAddress, NumberOfRegisters}, 
             Callback = #async_response{}},
            State = #state{unit_id = UnitId}) ->
    {Result, NState} = 
        read_holding_registers(StartAddress, NumberOfRegisters, UnitId, State),
    RState = invoke_callback(Result, Callback, NState),
    {noreply, RState};

%%----------------------------------------------------------------------------
%% read_input_registers
%%----------------------------------------------------------------------------

handle_cast({{read_input_registers, StartAddress, NumberOfRegisters}, 
             Callback = #async_response{}},
            State = #state{unit_id = UnitId}) ->
    {Result, NState} = 
        read_input_registers(StartAddress, NumberOfRegisters, UnitId, State),
    RState = invoke_callback(Result, Callback, NState),
    {noreply, RState};

%%----------------------------------------------------------------------------
%% write_single_register
%%---------------------------------------------------------------------------

handle_cast({{write_single_register, RegisterAddress, Value}, 
             Callback = #async_response{}},
            State = #state{unit_id = UnitId}) ->
    {Result, NState} = 
        write_single_register(RegisterAddress, Value, UnitId, State),
    RState = invoke_callback(Result, Callback, NState),
    {noreply, RState};

%%----------------------------------------------------------------------------
%% write_multiple_registers
%%---------------------------------------------------------------------------

handle_cast({{write_multiple_registers, 
              StartAddress, 
              NumberOfRegisters, 
              Values}, 
             Callback = #async_response{}},
            State = #state{unit_id = UnitId}) ->
    {Result, NState} = 
        write_multiple_registers(StartAddress, 
                                 NumberOfRegisters, 
                                 Values, 
                                 UnitId,
                                 State),
    RState = invoke_callback(Result, Callback, NState),
    {noreply, RState};

%%----------------------------------------------------------------------------
%% Unknown cast expression
%%----------------------------------------------------------------------------

handle_cast(Expr, State) ->
    ?LogIt({handle_cast, unknown}, "Unknown expr: ~n~p. ~nIgnoring", [Expr]),
    {noreply, State}.

%%----------------------------------------------------------------------------
%% handle_info
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% Unknown info expression
%%----------------------------------------------------------------------------

handle_info(Expr, State) ->
    ?LogIt({handle_info, unknown}, "Unknown expr: ~n~p. ~nIgnoring", [Expr]),
    {noreply, State}.

%%----------------------------------------------------------------------------
%% handle_pipe
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% read_holding_registers
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, 
             read_holding_registers, 
             {StartAddress, NumberOfRegisters}}, 
            State = #state{unit_id = UnitId}) ->
    {Result, NState} = 
        read_holding_registers(StartAddress, NumberOfRegisters, UnitId, State),
    {reply, Result, SessionId, NState};

%%----------------------------------------------------------------------------
%% read_input_registers
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, 
             read_input_registers, 
             {StartAddress, NumberOfRegisters}}, 
            State = #state{unit_id = UnitId}) ->
    {Result, NState} = 
        read_input_registers(StartAddress, NumberOfRegisters, UnitId, State),
    {reply, Result, SessionId, NState};

%%----------------------------------------------------------------------------
%% write_single_register
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, 
             write_single_register, 
             {RegisterAddr, Value}}, 
            State = #state{unit_id = UnitId}) ->
    {Result, NState} = 
        write_single_register(RegisterAddr, Value, UnitId, State),
    {reply, Result, SessionId, NState};

%%----------------------------------------------------------------------------
%% write_multiple_registers
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, 
             write_multiple_registers, 
             {StartAddress, NumberOfRegisters, Values}}, 
            State = #state{unit_id = UnitId}) ->
    {Result, NState} = 
        write_multiple_registers(StartAddress, 
                                 NumberOfRegisters, 
                                 Values, 
                                 UnitId,
                                 State),
    {reply, Result, SessionId, NState};

%%----------------------------------------------------------------------------
%% Unknown pipe expression
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, _Term, Expr}, State) ->
    % Skips to next in pipe
    {reply, Expr, SessionId, State}.

%%----------------------------------------------------------------------------
%% Exported Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% "Spawn" Behavior
%%----------------------------------------------------------------------------

spawn(nolink, Name = {global, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(nolink, Name, NStartArgs, StartOptions);
spawn(nolink, Name = {local, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(nolink, Name, NStartArgs, StartOptions);
spawn(link, Name = {global, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(link, Name, NStartArgs, StartOptions);
spawn(link, Name = {local, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(link, Name, NStartArgs, StartOptions).

spawn(nolink, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(nolink, NStartArgs, StartOptions);
spawn(link, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(link, NStartArgs, StartOptions).

%%----------------------------------------------------------------------------
%% Internal Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% read_holding_registers
%%----------------------------------------------------------------------------

read_holding_registers(StartAddress, NumberOfRegisters, UnitId, State) ->
    {TransId, TState} = create_transaction_id(State),
    FunctionCode = ?ReadHoldingRegisters,
    PDU = <<FunctionCode:8,StartAddress:16,NumberOfRegisters:16>>,
    attempt_send_and_receive(#request_id{trans_id = TransId, 
                                         unit_id = UnitId},
                             PDU, 
                             fun read_holding_registers_response/3, 
                             TState).

%%----------------------------------------------------------------------------
%% read_holding_registers_response
%%----------------------------------------------------------------------------

% More abstraction is available between requests given common exception 
%    handling. REVISIT

read_holding_registers_response(_RequestId, 
                                <<1:1,
                                  (?ReadHoldingRegisters):7,
                                  Exception:8>>, 
                                State) ->
    {{exception, generate_exception_code(Exception)}, State};
read_holding_registers_response(_RequestId, 
                                <<(?ReadHoldingRegisters):8,
                                  NumBytes:8,
                                  Data/bitstring>>, 
                                State) ->
    NumRegisters = NumBytes bsr 1,
    {{ok, convert_byte_data_to_words(NumRegisters, Data)}, State};
read_holding_registers_response(_RequestId, 
                                <<_BadFunctionCode:8,
                                  _NumBytes:8,
                                  _Data/bitstring>>, 
                                State) ->
    {{error, bad_function_code}, State}.

%%----------------------------------------------------------------------------
%% read_input_registers
%%----------------------------------------------------------------------------

read_input_registers(StartAddress, NumberOfRegisters, UnitId, State) ->
    {TransId, TState} = create_transaction_id(State),
    FunctionCode = ?ReadInputRegisters,
    PDU = <<FunctionCode:8,StartAddress:16,NumberOfRegisters:16>>,
    attempt_send_and_receive(#request_id{trans_id = TransId, 
                                         unit_id = UnitId},
                             PDU, 
                             fun read_input_registers_response/3, 
                             TState).

%%----------------------------------------------------------------------------
%% read_input_registers_response
%%----------------------------------------------------------------------------

% More abstraction is available between requests given common exception 
%    handling. REVISIT

read_input_registers_response(_RequestId, 
                              <<1:1,
                                (?ReadInputRegisters):7,
                                Exception:8>>, 
                              State) ->
    {{exception, generate_exception_code(Exception)}, State};
read_input_registers_response(_RequestId, 
                              <<(?ReadInputRegisters):8,
                                NumBytes:8,
                                Data/bitstring>>, 
                              State) ->
    NumRegisters = NumBytes bsr 1,
    {{ok, convert_byte_data_to_words(NumRegisters, Data)}, State};
read_input_registers_response(_RequestId, 
                              <<_BadFunctionCode:8,
                                _NumBytes:8,
                                _Data/bitstring>>, 
                              State) ->
    {{error, bad_function_code}, State}.

%%----------------------------------------------------------------------------
%% write_single_register
%%----------------------------------------------------------------------------

write_single_register(RegisterAddr, Value, UnitId, State) ->
    {TransId, TState} = create_transaction_id(State),
    FunctionCode = ?WriteSingleRegister,
    PDU = <<FunctionCode:8,RegisterAddr:16,Value:16>>,
    attempt_send_and_receive(#request_id{trans_id = TransId, 
                                         unit_id = UnitId},
                             PDU, 
                             fun write_single_register_response/3, 
                             TState).

%%----------------------------------------------------------------------------
%% write_single_register_response
%%----------------------------------------------------------------------------

% More abstraction is available between requests given common exception 
%    handling. REVISIT

write_single_register_response(_RequestId, 
                               <<1:1,
                                 (?WriteSingleRegister):7,
                                 Exception:8>>, 
                               State) ->
    {{exception, generate_exception_code(Exception)}, State};
write_single_register_response(_RequestId, 
                               <<(?WriteSingleRegister):8,
                                 _RegisterAddr:16,
                                 _RegisterValue:16>>, 
                               State) ->
    {ok, State};
write_single_register_response(_RequestId, 
                               <<_BadFunctionCode:8,
                                 _RegisterAddr:8,
                                 _RegisterValue:16>>,
                               State) ->
    {{error, bad_function_code}, State}.

%%----------------------------------------------------------------------------
%% write_multiple_registers
%%----------------------------------------------------------------------------

write_multiple_registers(StartAddress, Number, Values, UnitId, State) when
        Number =< length(Values) ->
    {TransId, TState} = create_transaction_id(State),
    NValues = lists:sublist(Values, Number),
    {EncodedValues, EState} = 
        encode_register_values(Number, NValues, TState),
    FunctionCode = ?WriteMultipleRegisters,
    PDU = <<FunctionCode:8, 
            StartAddress:16, 
            Number:16, 
            (Number bsl 1):8,
            EncodedValues/bitstring>>,
    attempt_send_and_receive(#request_id{trans_id = TransId, 
                                         unit_id = UnitId},
                             PDU, 
                             fun write_multiple_registers_response/3, 
                             EState);
write_multiple_registers(_StartAddress, _Number, _Values, _UnitId, State) ->
    {{error, bad_request}, State}.

%%----------------------------------------------------------------------------
%% write_multiple_registers_response
%%----------------------------------------------------------------------------

% More abstraction is available between requests given common exception 
%    handling. REVISIT

write_multiple_registers_response(_RequestId, 
                                  <<1:1,
                                    (?WriteMultipleRegisters):7,
                                    Exception:8>>, 
                                  State) ->
    {{exception, generate_exception_code(Exception)}, State};
write_multiple_registers_response(_RequestId, 
                                  <<(?WriteMultipleRegisters):8,
                                    _StartAddr:16,
                                    _NumRegisters:16>>, 
                                  State) ->
    {ok, State};
write_multiple_registers_response(_RequestId, 
                                  <<_BadFunctionCode:8,
                                    _StartAddr:8,
                                    _NumRegisters:16>>,
                                  State) ->
    {{error, bad_function_code}, State}.

%%----------------------------------------------------------------------------
%% generate_exception_code
%%----------------------------------------------------------------------------

generate_exception_code(Exception) ->
    case Exception of
        1 -> illegal_function;
        2 -> illegal_data_address;
        3 -> illegal_data_value;
        4 -> server_device_failure;
        5 -> acknowledge;
        6 -> server_device_busy;
        8 -> memory_parity_error;
        10 -> gateway_path_unavailable;
        11 -> gateway_target_device_failed_to_respond
    end.

%%----------------------------------------------------------------------------
%% convert_byte_data_to_words
%%----------------------------------------------------------------------------

convert_byte_data_to_words(NumWords, BitString) ->
    {Result, _} =
        pur_utls_misc:iterate(
            NumWords, 
            {[], BitString},
            fun (_NCount, {Acc, <<Next:16,Rest/bitstring>>}) ->
                {true, {[Next|Acc], Rest}}
            end),
    lists:reverse(Result).

%%----------------------------------------------------------------------------
%% encode_register_values
%%----------------------------------------------------------------------------

encode_register_values(_NumRegisters, Values, State) ->
    Ret =
        lists:foldl(
            fun (Next, Acc) ->
                <<Acc/bitstring,Next:16>>
            end,
            <<>>,
            Values),
    {Ret, State}.
    
%%----------------------------------------------------------------------------
%% attempt_send_and_receive
%%----------------------------------------------------------------------------

attempt_send_and_receive(RequestId = #request_id{trans_id = TransId,
                                                 unit_id = UnitId}, 
                         PDU, 
                         ResponseFunction, 
                         State) ->
    MBAP = <<TransId:16, 0:16, (byte_size(PDU) + 1):16, UnitId:8>>,
    Request = <<MBAP/bitstring,PDU/bitstring>>,
    case attempt_send(Request, State) of
        {true, AState} ->
            case attempt_read(RequestId, AState) of
                {true, Incoming, RState} ->
                    ResponseFunction(RequestId, Incoming, RState);
                R = {{error, _Reason}, _RState} ->
                    R
            end;
        R = {{error, _Reason}, _AState} ->
            R
    end.

%%----------------------------------------------------------------------------
%% attempt_read
%%----------------------------------------------------------------------------

attempt_read(RequestId, State = #state{max_rerecv_count = Count}) ->
    attempt_read(Count, RequestId, State).

attempt_read(_NumTrys, _RequestId, State = #state{socket = undefined}) ->
    {{error, not_connected}, State};
attempt_read(NumTrys, RequestId, State) ->
    case pur_utls_misc:iterate(NumTrys, 
                               {ignore, RequestId, State}, 
                               fun try_read/2) of
        R = {true, _Result, _SState} -> R;
        {Status, _, SState} -> {Status, SState}
    end.

%%----------------------------------------------------------------------------
%% try_read
%%----------------------------------------------------------------------------

% We loose the original error.
try_read(_Count, {_, RequestId, State = #state{socket = undefined}}) ->
    {false, {{error, connection_failure}, RequestId, State}};
try_read(Count, Acc = {_, 
                       RequestId = #request_id{trans_id = _TransId,
                                               unit_id = _UnitId},
                       State = #state{socket = Socket, 
                                      hostname = Hostname,
                                      port = Port,
                                      recv_timeout = Timeout}}) ->
    case gen_tcp:recv(Socket, ?HeaderReceiveSize, Timeout) of
        {ok, Packet} ->
            retrieve_pdu(RequestId, Packet, State);
        {error, timeout} ->
            case Count of
                0 ->
                    % Trying twice on first attempt. Deals with cases where
                    %     server is using timeouts in its reads, and latency
                    %     of client and server are similar (such as when
                    %     both are running locally). Due to synchronous, 
                    %     iterative nature, of certain server implementations 
                    %     like pur_tcp_modbus_iter_server, (server's idle 
                    %     state is in a recv wait which times out to handle 
                    %     admin functions). 
                    %     Using pur_tcp_modbus_server in place of 
                    %     pur_tcp_modbus_iter_server removes this effect.
                    try_read(Count, Acc);
                _ ->
                    % Note: We are NOT treating this as an immediate error!
                    ?LogIt(try_read, 
                           "gen_tcp:recv(...) from host: ~p, port: ~p, failed "
                               "with timeout: ~p. May retry recv.",
                           [Hostname, Port, Timeout]),
                    {true, {{error, timeout}, RequestId, State}}
            end;
        {error, Reason} when Reason == ebadf;
                             Reason == econnreset;
                             Reason == epipe;
                             Reason == etimedout;
                             Reason == econnaborted;
                             Reason == enobufs  ->
            ?LogIt(try_read, 
                   "gen_tcp:recv(...) from host: ~p, port: ~p, failed "
                       "with: ~p, which is being treated as a designated "
                       "connection failure. Will not retry recv.",
                   [Hostname, Port, Reason]),
            CState = close(State),
            {false, {{error, connection_failure}, RequestId, CState}};
        {error, Reason} ->
            ?LogIt(try_read, 
                   "gen_tcp:recv(...) from host: ~p, port: ~p, failed "
                       "with: ~p, which is being treated as a possible "
                       "connection failure. Will not retry recv.",
                   [Hostname, Port, Reason]),
            CState = close(State),
            {false, {{error, connection_failure}, RequestId, CState}}
    end.

%%----------------------------------------------------------------------------
%% retrieve_pdu
%%----------------------------------------------------------------------------

retrieve_pdu(RequestId, Payload, State) ->
    retrieve_pdu(first, RequestId, Payload, State).

retrieve_pdu(Try,
             RequestId = #request_id{trans_id = TransId,
                                     unit_id = UnitId},
             Payload,
             State = #state{socket = Socket, 
                            hostname = Hostname,
                            port = Port,
                            recv_timeout = Timeout}) ->
    Ret = 
        case Payload of
            <<TransId:16,_:16,Length:16>> ->
                case gen_tcp:recv(Socket, Length, Timeout) of
                    {ok, <<UnitId:8,PDU/bitstring>>} ->
                        {false, {true, PDU, State}};
                    {ok, <<OUnitId:8,_PDU/bitstring>>} ->
                        ?LogIt(retrieve_pdu, 
                               "gen_tcp:recv(...) from host: ~p, port: "
                                   "~p, PDU retrieval received wrong unit "
                                   "id: ~p, while waiting for unit "
                                   "id: ~p. May try again.",
                               [Hostname, Port, OUnitId, UnitId]),
                        {true, {{error, wrong_unit_id}, RequestId, State}}; 
                    {error, timeout} ->
                        % Hack. Implies that this gen_server should be a
                        %     fsm, or the retrieve_pdu(...) behavior should be
                        %     at lease be driven from the try_read(...) 
                        %     iterate count behaviour above. REVISIT
                        retrieve_pdu(second, RequestId, Payload, State);
                    {error, Reason} ->
                        ?LogIt(retrieve_pdu, 
                               "gen_tcp:recv(...) from host: ~p, port: "
                                   "~p, failed for PDU retrieval with: "
                                   "~p. This is being treated as a "
                                   "connection failure where this modbus "
                                   "read will fail, and result in a "
                                   "closed connection.",
                               [Hostname, Port, Reason]),
                        CState = close(State),
                        {false, {{error, Reason}, RequestId, CState}}
                end;
            % Ignoring MBAP protocol field
            <<OTransId:16,_:16,Length:16>> ->
                ?LogIt(retrieve_pdu, 
                       "gen_tcp:recv(...) from host: ~p, port: "
                           "~p, received wrong transaction id: ~p. "
                           "Expecting transaction id: ~p. May try again.",
                       [Hostname, Port, OTransId, TransId]),
                case gen_tcp:recv(Socket, Length, Timeout) of
                    {ok, _} ->
                        {true, {{error, wrong_trans_id}, RequestId, State}};
                    _ ->
                        ?LogIt(retrieve_pdu, 
                               "gen_tcp:recv(...) from host: ~p, port: "
                                   "~p, wrong transaction id: ~p, "
                                   "PDU not retrievable. Reseting connection "
                                   "and failing original request.",
                               [Hostname, Port, OTransId]),
                        CState = close(State),
                        {false, {{error, wrong_trans_id}, RequestId, CState}}
                end
        end,
    if 
        Try == first ->
            Ret;
        true ->
            case Ret of
                {true, {Status, RequestId, NState}} ->
                    ?LogIt(retrieve_pdu, 
                           "gen_tcp:recv(...) from host: ~p, port: "
                               "~p, failed for second PDU retrieval. "
                               "This is being treated as a connection "
                               "failure where this modbus read will fail, "
                               "and close the connection.",
                           [Hostname, Port]),
                    CCState = close(NState),
                    {false, {Status, RequestId, CCState}};
                _ ->
                    Ret
            end
    end.

%%----------------------------------------------------------------------------
%% attempt_send
%%----------------------------------------------------------------------------

attempt_send(Request, State = #state{max_resend_count = Count}) ->
    attempt_send(Count, Request, State).

attempt_send(NumTrys, Request, State = #state{socket = undefined}) ->
    case reconnect(State) of
        {true, CState} ->
            attempt_send(NumTrys, Request, CState);
        {false, CState} ->
            {{error, connection_failure}, CState}
    end;
attempt_send(NumTrys, Request, State) ->
    case pur_utls_misc:iterate(NumTrys, 
                               {ignore, 0, Request, State}, fun 
                               send_request/2) of
        R = {true, _SState} ->
            R;
        {{error, Reason}, NumTrys, _, SState} ->
            {{error, Reason}, SState};
        {{error, _Reason}, LastTryCount, _, SState} ->
            attempt_send(NumTrys - LastTryCount, Request, SState)
    end.

%%----------------------------------------------------------------------------
%% send_request
%%----------------------------------------------------------------------------

% We loose the original error.
send_request(Count, {_, _, Request, State = #state{socket = undefined}}) ->
    {false, {{error, connection_failure}, Count + 1, Request, State}};
send_request(Count, {_, _, Request, State = #state{socket = Socket, 
                                                   hostname = Hostname,
                                                   port = Port}}) ->
    case gen_tcp:send(Socket, Request) of
        ok ->
            {false, {true, State}};
        {error, Reason} when Reason == timeout ->
            % Note: We are NOT treating this as an immediate error!
            ?LogIt(send_request, 
                   "gen_tcp:send(...) to host: ~p, port: ~p, failed "
                       "with: ~p. May retry send.",
                   [Hostname, Port, Reason]),
            {true, {{error, timeout}, Count + 1, Request, State}};
        {error, Reason} when Reason == ebadf;
                             Reason == econnreset;
                             Reason == epipe;
                             Reason == etimedout;
                             Reason == econnaborted;
                             Reason == enobufs  ->
            ?LogIt(send_request, 
                   "gen_tcp:send(...) to host: ~p, port: ~p, failed "
                       "with: ~p, which is being treated as a designated "
                       "connection failure. May retry connection, and "
                       "subsequent send.",
                   [Hostname, Port, Reason]),
            CState = close(State),
            {false, {{error, connection_failure}, Count + 1, Request, CState}};
        {error, Reason} when Reason == ecomm ->
            ?LogIt(send_request, 
                   "gen_tcp:send(...) to host: ~p, port: ~p, failed "
                       "with: ~p. May retry send.",
                   [Hostname, Port, Reason]),
            {true, {{error, Reason}, Count + 1, Request, State}};
        {error, Reason} ->
            ?LogIt(send_request, 
                   "gen_tcp:send(...) to host: ~p, port: ~p, failed "
                       "with: ~p, which is being treated as a possible "
                       "connection failure. May retry connection, and "
                       "subsequent send.",
                   [Hostname, Port, Reason]),
            CState = close(State),
            {false, {{error, connection_failure}, Count + 1, Request, CState}}
    end.

%%----------------------------------------------------------------------------
%% reconnect
%%----------------------------------------------------------------------------

reconnect(State = #state{max_reconnect_count = Count, socket = undefined}) ->
   case pur_utls_misc:iterate(Count, {ignore, State}, fun try_reconnect/2) of
       R = {true, _CState} -> R;
       {{error, _LastReason}, CState} -> {false, CState}
   end;
reconnect(State) ->
    CState = close(State),
    reconnect(CState).

%%----------------------------------------------------------------------------
%% try_reconnect
%%----------------------------------------------------------------------------

try_reconnect(_Count, {_,
                       State = #state{hostname = Hostname, 
                                      port = Port, 
                                      connect_options = Options}}) ->
    case gen_tcp:connect(Hostname, 
                         Port, 
                         Options, 
                         ?DefaultConnectTimeout) of
        R = {error, Reason} ->
            ?LogIt(try_reconnect, 
                   "gen_tcp:connect(...) to host: ~p, port: ~p, failed "
                       "with: ~p. May retry.",
                   [Hostname, Port, Reason]),
            {true, {R, State}};
        {ok, Socket} ->
            ?LogIt(try_reconnect, 
                   "gen_tcp:connect(...) Succeeded to host: ~p, port: ~p.",
                   [Hostname, Port]),
            {false, {true, State#state{socket = Socket}}}
    end.

%%----------------------------------------------------------------------------
%% close
%%----------------------------------------------------------------------------

close(State = #state{socket = undefined}) ->
    State;
close(State = #state{socket = Socket}) ->
    gen_tcp:shutdown(Socket, read),
    gen_tcp:close(Socket),
    State#state{socket = undefined}.

%%----------------------------------------------------------------------------
%% invoke_callback
%%----------------------------------------------------------------------------

invoke_callback(Result, 
                #async_response{server = undefined, 
                                module = undefined, 
                                function = Function,
                                state = ResState}, 
                State) ->
    Function(Result, ResState),
    State;
invoke_callback(Result, 
                #async_response{server = undefined, 
                                module = Module, 
                                function = Function,
                                state = ResState}, 
                State) ->
    Module:Function(Result, ResState),
    State;
invoke_callback(Result, 
                #async_response{server = Server, 
                                module = undefined, 
                                function = Function,
                                state = ResState}, 
                State) ->
    Function(Server, Result, ResState),
    State;
invoke_callback(Result, 
                #async_response{server = Server, 
                                module = Module, 
                                function = Function,
                                state = ResState}, 
                State) ->
    Module:Function(Server, Result, ResState),
    State.

%%----------------------------------------------------------------------------
%% create_transaction_id
%%----------------------------------------------------------------------------

create_transaction_id(State = #state{next_trans_id = Ret}) ->
    NextTransId = ((Ret + 1) rem 16#FFFF) + 1,
    {Ret, State#state{next_trans_id = NextTransId}}.
