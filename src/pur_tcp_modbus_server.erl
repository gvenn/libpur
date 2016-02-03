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

-module(pur_tcp_modbus_server).

-behavior(pur_utls_pipe_server).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% This implementation uses the server module pur_utls_recv_slave to handle
%%     received requests much like gen_tcp does in active mode with option
%%     {header, Size} used. However in this case pur_utls_recv_slave
%%     is used to provide control how long the read payload should be, not
%%     just control of the header length.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-export([spawn/4, spawn/3,
         handle_call/3, handle_cast/2, handle_info/2, handle_pipe/2,
         terminate/2, code_change/3,
         parse_header_for_pdu_size/2, 
         init/1]).

-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_props.hrl").
-include_lib("pur_utls_pipes.hrl").
-include_lib("pur_tcp_modbus.hrl").
-include_lib("pur_tcp_modbus_server.hrl").

%%----------------------------------------------------------------------------
%% Records
%%----------------------------------------------------------------------------

% Send logic WILL re-attempt connection establishment on failure
-define(DefaultMaxResendCount, 5).
% Recv logic WILL NOT re-attempt connection establishment on failure
-define(DefaultMaxRerecvCount, 3).
-define(DefaultMaxReconnectCount, 10).

-define(DefaultUnitId, 16#FF).
-define(DefaultRecvTimeout, 100).
-define(HeaderReceiveSize, 6).
-define(ReadHoldingRegisters, 16#03).
-define(ReadInputRegisters, 16#04).
-define(WriteSingleRegister, 16#06).
-define(WriteMultipleRegisters, 16#10).

% Exceptions
-define(IllegalFunction, 1).
-define(IllegalDataAddress, 2).
-define(IllegalDataValue, 3).
-define(ServerDeviceFailure, 4).
-define(Acknowledge, 5).
-define(ServerDeviceBusy, 6).
-define(MemoryParityError, 8).
-define(GatewayPathUnavailable, 10).
-define(GatewayTargetDeviceFailedToRespond, 11).

% One server instance per hostname/port combination with synchronous behaviour

-record(state, {socket,
                max_resend_count,
                service_pipe,
                next_request_id = 0,
                % Not really used
                recv_server,
                server_ref = make_ref()}).

%%----------------------------------------------------------------------------
%% "Init" Behavior
%%----------------------------------------------------------------------------

init(Props) -> 
    InitFunctions = 
        [fun initialize_service_pipe/3,
         fun start_recv_server/3],
    pur_utls_server:auto_init(
        Props,
        [#propdesc{name = "socket",
                   index = #state.socket,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "service_pipe",
                   index = #state.service_pipe,
                   directive = required,
                   dirvalue = false},
         #propdesc{name = "max_resend_count",
                   index = #state.max_resend_count,
                   ret_type = integer,
                   directive = default,
                   dirvalue = ?DefaultMaxResendCount}],
        InitFunctions,
        ok,
        #state{}).

terminate(Reason, State) ->
    CState = close(State),
    ?LogIt(
        terminate,
        "Terminated for reason: ~n~p, ~nwith state:~n~p.",
        [Reason, CState]). 

code_change(_, State, _) -> 
    {ok, State}.

%%----------------------------------------------------------------------------
%% Genserver Exported Behavior
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% handle_call
%%----------------------------------------------------------------------------

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
%% exit_service
%%----------------------------------------------------------------------------

handle_cast({exit_service, _Ref}, State) ->
    NState = close(State),
    exit(normal),
    {noreply, NState};

%%----------------------------------------------------------------------------
%% close
%%----------------------------------------------------------------------------

handle_cast(close, State) ->
    NState = close(State),
    % Should not return. May have to use kill versus normal.
    exit(normal),
    {noreply, NState};

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
%% handle_received_payload pipe expression
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, 
             handle_received_payload, 
             {MBAP, PDU}}, 
            State) ->
    RState = handle_received_payload(MBAP, PDU, State),
    {noreply, SessionId, RState};

%%----------------------------------------------------------------------------
%% handle_response pipe expression
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, 
             handle_response, 
             {Id = #response_id{}, RequestData, Result}}, 
            State) ->
    % In the future the session id could be leveraged to set a context
    %     per request in the use of pur_utls_pipes:send_to_next(...).
    %     Timeouts could then be setup that would generate exceptions for
    %     for these "sessions". Currently we are expecting the client to 
    %     time out.
    NState =
        handle_response(Id, RequestData, Result, State),
    {noreply, SessionId, NState};

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
%% initialize_service_pipe
%%----------------------------------------------------------------------------

initialize_service_pipe(Props, 
                        _Context, 
                        State = #state{service_pipe = undefined}) ->
    Result = pur_utls_props:set_from_props(
                 Props, 
                 [#propdesc{name = "pipe_endpoint",
                           index = 1,
                           ret_type = atom,
                           directive = required,
                           dirvalue = true},
                  #propdesc{name = "pipe_build_term",
                            index = 2,
                            ret_type = atom,
                            directive = required,
                            dirvalue = true}],
                 erlang:make_tuple(2, 0)),
    case Result of
        {true, {Server, Term}} ->
            % Allow exception on failure
            NPipe = [#pipecomp{}|_] = gen_server:call(Server, Term),
            {true, add_return_pipe_comp(State#state{service_pipe = NPipe})};
        {false, Reason, _} -> 
            ?LogIt(
                initialize_service_pipe, 
                "Props: ~n~p, ~ndo not have correct service pipe call "
                    "parameters.",
                [Props]),
            {false, Reason, State}
    end;
initialize_service_pipe(_Props, 
                        _Context, 
                        State = #state{service_pipe = [#pipecomp{}|_]}) ->
        {true, add_return_pipe_comp(State)};
initialize_service_pipe(_Props, _Context, State) ->
    LogMessage = ?LogItMessage(
                     init, 
                     "Service Pipe is NOT correctly constructed. "
                         "Exiting."),
    ?LogItRaw(LogMessage),
    {false, LogMessage, State}.

%%----------------------------------------------------------------------------
%% start_recv_server
%%----------------------------------------------------------------------------

start_recv_server(_Props, _Context, State = #state{socket = Socket}) ->
    PipeComp = #pipecomp{name = "process_payload", 
                         pipe_name = "payload_receiver",
                         type = cast,
                         exec = handle_received_payload,
                         to = self()},
    Args = [{socket, Socket}, 
            {service_pipe, [PipeComp]}, 
            {service_session_id, "payload_session"},
            {header_size, ?HeaderReceiveSize},
            {header_handler, fun ?MODULE:parse_header_for_pdu_size/2},
            {header_handler_context, ok}],
    case pur_utls_recv_slave:spawn(link, Args, []) of
        {ok, Pid} ->
            {true, State#state{recv_server = Pid}};
        Reason ->
            {false, Reason, State}
    end.

%%----------------------------------------------------------------------------
%% parse_header_for_pdu_size
%%----------------------------------------------------------------------------

% Not a gen_server function (no state), just a POF
parse_header_for_pdu_size(<<_TransId:16,_:16,Length:16>>, _) ->
    {ok, Length};
parse_header_for_pdu_size(Header, _) ->
    Reason = 
        ?LogItMessage(parse_header_for_pdu_size,
                      "Bad header: ~p, received.",
                      [Header]),
    ?LogItRaw(Reason),
    {error, Reason}.

%%----------------------------------------------------------------------------
%% add_return_pipe_comp
%%----------------------------------------------------------------------------

add_return_pipe_comp(State = #state{service_pipe = Pipe = 
                                        [#pipecomp{pipe_name = PName}|_]}) ->
    PipeComp = #pipecomp{name = "tcp_modbus_server",
                         type = cast,
                         exec = handle_response,
                         to = self(),
                         pipe_name = PName},
    NPipe = Pipe ++ [PipeComp],
    State#state{service_pipe = NPipe}.

%%----------------------------------------------------------------------------
%% exit_service
%%----------------------------------------------------------------------------

exit_service(State = #state{server_ref = Ref}) ->
    gen_server:cast(self(), {exit_service, Ref}),
    State.

%%----------------------------------------------------------------------------
%% close
%%----------------------------------------------------------------------------

close(State = #state{socket = undefined, recv_server = undefined}) ->
    State;
close(State = #state{socket = undefined, recv_server = Server}) ->
    gen_server:cast(Server, close),
    State#state{recv_server = undefined};
close(State = #state{socket = Socket, recv_server = undefined}) ->
    gen_tcp:shutdown(Socket, read),
    gen_tcp:close(Socket),
    State#state{socket = undefined};
close(State = #state{recv_server = Server}) ->
    gen_server:cast(Server, close),
    close(State#state{recv_server = undefined}).

%%----------------------------------------------------------------------------
%% handle_received_payload
%%----------------------------------------------------------------------------

handle_received_payload(<<TransId:16,_:16,_Length:16>>, 
                        <<UnitId:8,PDU/bitstring>>, 
                        State) ->
    ResponseId = #response_id{trans_id = TransId, unit_id = UnitId},
    forward_request(ResponseId, PDU, State);
handle_received_payload(MBAP, PDU, State) ->
    ?LogIt(handle_received_payload,
           "Bad MBAP: ~p, or PDU: ~p, received. Exiting.",
           [MBAP, PDU]),
    CState = close(State),
    exit_service(CState).

%%----------------------------------------------------------------------------
%% forward_request
%%----------------------------------------------------------------------------

forward_request(Id = #response_id{}, PDU, State) ->
    % Redundance between function code, and request term. Not sure function
    %    code will not be needed by actual server. REVISIT
    case PDU of
        <<(?ReadHoldingRegisters):8,RequestData/bitstring>> ->
            handle_read_registers_request(
                Id#response_id{funct_code = ?ReadHoldingRegisters}, 
                read_holding_registers,
                RequestData, 
                State);
        <<(?ReadInputRegisters):8,RequestData/bitstring>> ->
            handle_read_registers_request(
                Id#response_id{funct_code = ?ReadInputRegisters}, 
                read_input_registers,
                RequestData, 
                State);
        <<(?WriteSingleRegister):8,RegisterAddr:16,RegisterValue:16>> ->
            handle_write_registers_request(
                Id#response_id{funct_code = ?WriteSingleRegister}, 
                write_single_register,
                {RegisterAddr, 1, [RegisterValue]}, 
                State);
        <<(?WriteMultipleRegisters):8,RequestData/bitstring>> ->
            handle_write_registers_request(
                Id#response_id{funct_code = ?WriteMultipleRegisters}, 
                write_multiple_registers,
                RequestData, 
                State);
        <<UnknownFunctionCode:8,_UnknownRequestData/bitstring>> ->
            ?LogIt(forward_request,
                   "Unknown PDU with function code: ~p, received. Ignoring.",
                   [UnknownFunctionCode]),
            Exception = generate_exception_code(illegal_function),
            send_pdu_response(Id,
                              <<1:1,(UnknownFunctionCode):7,Exception:8>>, 
                              State) 
    end.

%%----------------------------------------------------------------------------
%% handle_read_registers_request
%%----------------------------------------------------------------------------

handle_read_registers_request(Id, 
                              RequestTerm,
                              <<StartAddress:16, NumberOfRegisters:16>>, 
                              State = #state{service_pipe = Pipe}) ->
    {RequestId, RState} = create_request_id(State),
    Request = {Id#response_id{request_id = RequestId},
               {RequestTerm,
                StartAddress,
                NumberOfRegisters}},
    % Use same request id as session id for now. REVISIT.
    pur_utls_pipes:send_to_next(Request, RequestId, Pipe),
    RState;
handle_read_registers_request(Id, RequestTerm, _RequestData, State) ->
    ?LogIt(handle_read_registers_request, 
           "Request data for request: ~p, is incorrect.",
           [RequestTerm]),
    Exception = generate_exception_code(illegal_data_value),
    send_pdu_response(Id,
                      <<1:1,(Id#response_id.funct_code):7,Exception:8>>, 
                      State). 

%%----------------------------------------------------------------------------
%% handle_write_registers_request
%%----------------------------------------------------------------------------

handle_write_registers_request(Id, 
                               RequestTerm,
                               {StartAddress, NumberOfRegisters, Values},
                               State = #state{service_pipe = Pipe}) ->
    {RequestId, RState} = create_request_id(State),
    Request = {Id#response_id{request_id = RequestId},
               {RequestTerm,
                StartAddress,
                NumberOfRegisters,
                Values}},
    % Use same request id as session id for now. REVISIT.
    pur_utls_pipes:send_to_next(Request, RequestId, Pipe),
    RState;
handle_write_registers_request(Id, 
                               RequestTerm,
                               <<StartAddress:16, 
                                 NumberOfRegisters:16, 
                                 ByteCount:8, 
                                 BitValue/bitstring>>,
                               State = #state{service_pipe = Pipe}) when
        (ByteCount bsr 1) == NumberOfRegisters ->
    {Values, DState} = decode_register_values(NumberOfRegisters, 
                                              BitValue, 
                                              State),
    {RequestId, RState} = create_request_id(DState),
    Request = {Id#response_id{request_id = RequestId},
               {RequestTerm,
                StartAddress,
                NumberOfRegisters,
                Values}},
    % Use same request id as session id for now. REVISIT.
    pur_utls_pipes:send_to_next(Request, RequestId, Pipe),
    RState;
handle_write_registers_request(Id, 
                               _RequestTerm,
                               <<_StartAddress:16, 
                                 NumberOfRegisters:16, 
                                 ByteCount:8, 
                                 _Values/bitstring>>,
                                State) ->
    ?LogIt(handle_write_registers_request,
           "Byte count: (~p << 1), does not match number of registers: ~p, "
               "for request: ~p.",
           [ByteCount, NumberOfRegisters, _RequestTerm]),
    Exception = generate_exception_code(illegal_data_value),
    send_pdu_response(Id,
                      <<1:1,(Id#response_id.funct_code):7,Exception:8>>, 
                      State);
handle_write_registers_request(Id, RequestTerm, _RequestData, State) ->
    ?LogIt(handle_write_registers_request, 
           "Request data for request: ~p, is incorrect.",
           [RequestTerm]),
    Exception = generate_exception_code(illegal_data_value),
    send_pdu_response(Id,
                      <<1:1,(Id#response_id.funct_code):7,Exception:8>>, 
                      State). 

%%----------------------------------------------------------------------------
%% handle_response
%%----------------------------------------------------------------------------

handle_response(Id = #response_id{funct_code = Code}, 
                                  _RequestData, 
                                  {exception, Exception}, 
                                  State) ->
    ExCode = 
        case generate_exception_code(Exception) of
            undefined -> 
                ?LogIt(handle_response, 
                       "Received unknown exception: ~p. Defaulting to "
                           "illegal_data_value.",
                       [Exception]),
                generate_exception_code(illegal_data_value);
            R -> 
                R
        end,
    PDU = <<1:1,Code:7,ExCode:8>>,
    send_pdu_response(Id, PDU, State);
handle_response(Id,
                RequestData, 
                Result, 
                State) ->
    forward_response(Id, RequestData, Result, State).

%%----------------------------------------------------------------------------
%% forward_response
%%----------------------------------------------------------------------------

forward_response(Id = #response_id{funct_code = Code}, 
                 RequestData, 
                 Result, 
                 State) ->
    % Redundance between function code, and request term. Not sure function
    %    code will not be needed by actual server. REVISIT
    case Code of
        ?ReadHoldingRegisters ->
            handle_read_registers_response(Id,
                                           RequestData, 
                                           Result,
                                           State);
        ?ReadInputRegisters ->
            handle_read_registers_response(Id,
                                           RequestData, 
                                           Result,
                                           State);
        ?WriteSingleRegister ->
            handle_write_single_register_response(Id,
                                                  RequestData, 
                                                  Result,
                                                  State);
        ?WriteMultipleRegisters ->
            handle_write_multiple_registers_response(Id,
                                                     RequestData, 
                                                     Result,
                                                     State);
        UnknownFunctionCode ->
            ?LogIt(forward_response,
                   "Function code: ~p returned by modbus server is unknown.",
                   [UnknownFunctionCode]),
            Exception = generate_exception_code(server_device_failure),
            send_pdu_response(Id,
                              <<1:1,(UnknownFunctionCode):7,Exception:8>>, 
                              State) 
    end.

%%----------------------------------------------------------------------------
%% handle_read_registers_response
%%----------------------------------------------------------------------------

handle_read_registers_response(Id, _Request, RegisterValues, State) ->
    % May add boundary logic in the future 
    NumRegisters = length(RegisterValues),
    {EncodedValues, EState} = encode_register_values(NumRegisters, 
                                                     RegisterValues, 
                                                     State),
    PDU = <<(Id#response_id.funct_code):8,
            (NumRegisters bsl 1):8,
            EncodedValues/bitstring>>,
    send_pdu_response(Id, PDU, EState).

%%----------------------------------------------------------------------------
%% handle_write_single_register_response
%%----------------------------------------------------------------------------

handle_write_single_register_response(Id, 
                                      {_, BaseAddr, _, [Value]}, 
                                      _Result, 
                                      State) ->
    PDU = <<(Id#response_id.funct_code):8, BaseAddr:16, Value:16>>,
    send_pdu_response(Id, PDU, State).

%%----------------------------------------------------------------------------
%% handle_write_multiple_registers_response
%%----------------------------------------------------------------------------

handle_write_multiple_registers_response(Id, 
                                         {_, BaseAddr, _, _}, 
                                         Number, 
                                         State) ->
    PDU = <<(Id#response_id.funct_code):8, BaseAddr:16, Number:16>>,
    send_pdu_response(Id, PDU, State).

%%----------------------------------------------------------------------------
%% send_pdu_response
%%----------------------------------------------------------------------------

send_pdu_response(_Id, _PDU, State = #state{socket = undefined}) ->
    State;
send_pdu_response(#response_id{trans_id = TransId, unit_id = UnitId}, 
                  PDU, 
                  State) ->
    MBAP = <<TransId:16,0:16,(byte_size(PDU) + 1):16,UnitId:8>>,
    Response = <<MBAP/bitstring,PDU/bitstring>>,
    case attempt_send(Response, State) of
        {true, AState} -> 
            AState;
        {{error, _Reason}, AState} ->
            AState
    end.

%%----------------------------------------------------------------------------
%% generate_exception_code
%%----------------------------------------------------------------------------

generate_exception_code(Exception) ->
    case Exception of
        illegal_function ->
            ?IllegalFunction;
        illegal_data_address ->
            ?IllegalDataAddress;
        illegal_data_value ->
            ?IllegalDataValue;
        server_device_failure ->
            ?ServerDeviceFailure;
        acknowledge ->
            ?Acknowledge;
        server_device_busy ->
            ?ServerDeviceBusy;
        memory_parity_error ->
            ?MemoryParityError;
        gateway_path_unavailable ->
            ?GatewayPathUnavailable;
        gateway_target_device_failed_to_respond ->
            ?GatewayTargetDeviceFailedToRespond;
        _ ->
            undefined
    end.

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
%% decode_register_values
%%----------------------------------------------------------------------------

decode_register_values(NumWords, BitString, State) ->
    {Result, _} =
        pur_utls_misc:iterate(
            NumWords, 
            {[], BitString},
            fun (_NCount, {Acc, <<Next:16,Rest/bitstring>>}) ->
                {true, {[Next|Acc], Rest}}
            end),
    {lists:reverse(Result), State}.

%%----------------------------------------------------------------------------
%% attempt_send
%%----------------------------------------------------------------------------

attempt_send(Response, State = #state{max_resend_count = Count}) ->
    attempt_send(Count, Response, State).

attempt_send(_NumTrys, _Response, State = #state{socket = undefined}) ->
    {{error, connection_failure}, State};
attempt_send(NumTrys, Response, State) ->
    case pur_utls_misc:iterate(NumTrys, 
                               {ignore, Response, State}, fun 
                               send_response/2) of
        R = {true, _SState} ->
            R;
        {{error, Reason}, _, SState} ->
            {{error, Reason}, SState}
    end.

%%----------------------------------------------------------------------------
%% send_response
%%----------------------------------------------------------------------------

% We loose the original error.
send_response(_Count, {_, Response, State = #state{socket = undefined}}) ->
    {false, {{error, connection_failure}, Response, State}};
send_response(_Count, {_, Response, State = #state{socket = Socket}}) ->
    case gen_tcp:send(Socket, Response) of
        ok ->
            {false, {true, State}};
        {error, Reason} when Reason == timeout ->
            % Note: We are NOT treating this as an immediate error!
            ?LogIt(send_response, 
                   "gen_tcp:send(...) failed with: ~p. May retry send.",
                   [Reason]),
            {true, {{error, timeout}, Response, State}};
        {error, Reason} when Reason == ebadf;
                             Reason == econnreset;
                             Reason == epipe;
                             Reason == etimedout;
                             Reason == econnaborted;
                             Reason == enobufs  ->
            ?LogIt(send_response, 
                   "gen_tcp:send(...) failed with: ~p, which is being "
                       "treated as a designated connection failure. "
                       "Will exit.",
                   [Reason]),
            CState = close(State),
            EState = exit_service(CState),
            {false, {{error, connection_failure}, Response, EState}};
        {error, Reason} when Reason == ecomm ->
            ?LogIt(send_response, 
                   "gen_tcp:send(...) failed with: ~p. May retry send.",
                   [Reason]),
            {true, {{error, Reason}, Response, State}};
        {error, Reason} ->
            ?LogIt(send_response, 
                   "gen_tcp:send(...) failed with: ~p, which is being "
                       "treated as a possible connection failure. Will exit.",
                   [Reason]),
            CState = close(State),
            EState = exit_service(CState),
            {false, {{error, connection_failure}, Response, EState}}
    end.

%%----------------------------------------------------------------------------
%% create_request_id
%%----------------------------------------------------------------------------

create_request_id(State = #state{next_request_id = Ret}) ->
    % Arbitrarily Making it the same size as a modbus transaction id
    NextRequestId = ((Ret + 1) rem 16#FFFF) + 1,
    {Ret, State#state{next_request_id = NextRequestId}}.

