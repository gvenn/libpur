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

-module(pur_xdr_service).

-behavior(pur_utls_pipe_server).

-export([spawn/4, spawn/3,
         handle_call/3, handle_cast/2, handle_info/2, handle_pipe/2,
         terminate/2, code_change/3,
         init/1]).

-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_xdr.hrl").
-include_lib("pur_utls_props.hrl").
-include_lib("pur_utls_pipes.hrl").

%%----------------------------------------------------------------------------
%% Records
%%----------------------------------------------------------------------------

-record(state, {socket,
                xdr_codecs,
                header_length,
                header_decoder,
                xdr_args_map,
                service_pipe,
                % Not really used
                recv_server,
                read_with_actor,
                io = #io_funs{},
                server_ref = make_ref()}).

%%----------------------------------------------------------------------------
%% "Init" Behavior
%%----------------------------------------------------------------------------

init(Props) -> 
    InitFunctions =
        [fun (_NProps, _Context, State) ->
             {true, State#state{xdr_codecs = pur_utls_xdr:build_codecs()}}
         end,
         fun start_recv_server/3,
         fun build_io/3,
         fun start_service/3],
    pur_utls_server:auto_init(
        Props,
        [#propdesc{name = "socket",
                   index = #state.socket,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "header_length", 
                   index = #state.header_length,
                   ret_type = integer,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "header_decoder", 
                   index = #state.header_decoder,
                   directive = default,
                   dirvalue = fun retrieve_type_for_simple_header/1,
                   validation =
                       fun (ToCheck, _Props, _Desc, _Context, _TupleContext) ->
                           if
                               is_function(ToCheck, 1) ->
                                   ToCheck;
                               true ->
                                   {error, "header_decoder is not a "
                                               "function of arity 1."}
                           end
                       end},
         #propdesc{name = "xdr_args_map", 
                   index = #state.xdr_args_map,
                   ret_type = map,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "service_pipe", 
                   index = #state.service_pipe,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "read_with_actor", 
                   index = #state.read_with_actor,
                   directive = default,
                   dirvalue = true}],
        InitFunctions,
        [],
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
%% Unknown call expression
%%----------------------------------------------------------------------------

handle_call(Expr, _From, State) ->
    ?LogIt({handle_call, unknown}, "Unknown expr: ~n~p. ~nIgnoring", [Expr]),
    {reply, ok, State}.

%%----------------------------------------------------------------------------
%% handle_cast
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% close
%%----------------------------------------------------------------------------

handle_cast(close, State) ->
    CState = close(State),
    % Should not return. May have to use kill versus normal.
    {stop, normal, CState};

%%----------------------------------------------------------------------------
%% exit_service
%%----------------------------------------------------------------------------

handle_cast({exit_service, Ref}, State = #state{server_ref = Ref}) ->
    CState = close(State),
    {stop, normal, CState};

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
             PayloadResult}, 
            State) ->
    case handle_received_payload(PayloadResult, State) of
        {reply, Result, RState} ->
            {reply, Result, SessionId, RState};
        {noreply, RState} ->
            {noreply, SessionId, RState}
    end;

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
%% start_recv_server
%%----------------------------------------------------------------------------

start_recv_server(_Props, 
                  _Context, 
                  State = #state{socket = Socket, 
                                 service_pipe = Pipe}) ->
    PipeComp = #pipecomp{name = "process_payload", 
                         pipe_name = "payload_receiver",
                         type = cast,
                         exec = handle_received_payload,
                         to = self()},
    Args = [{socket, Socket}, 
            {service_pipe, [PipeComp|Pipe]}, 
            {service_session_id, "payload_session"}],
    case pur_utls_driven_recv_slave:spawn(link, Args, []) of
        {ok, Pid} ->
            {true, State#state{recv_server = Pid}};
        Reason ->
            {false, Reason, State}
    end.

%%----------------------------------------------------------------------------
%% build_io
%%----------------------------------------------------------------------------

build_io(_Props, _Context, State = #state{read_with_actor = true,
                                          recv_server = Server,
                                          io = Io}) ->
    Fun = 
        fun (NumToRead, NServer) ->
            R = gen_server:call(NServer, {read_next_payload, NumToRead}),
            {R, NServer}
        end,
    NIo = Io#io_funs{context = Server,
                     read_fun = Fun},
    {true, State#state{io = NIo}};
build_io(_Props, _Context, State = #state{recv_server = Server,
                                          io = Io}) ->
    case gen_server:call(Server, create_direct_call_handle) of
        {error, Reason} ->
            {false, Reason, State};
        {Fun, Handle} ->
            NIo = Io#io_funs{context = Handle,
                             read_fun = Fun},
            {true, State#state{io = NIo}}
    end.

%%----------------------------------------------------------------------------
%% start_service
%%----------------------------------------------------------------------------

start_service(_Props, _Context, State) ->
    {true, cont_service(State)}.

%%----------------------------------------------------------------------------
%% exit_service
%%----------------------------------------------------------------------------

exit_service(State = #state{server_ref = Ref}) ->
    gen_server:cast(self(), {exit_service, Ref}),
    State.

%%----------------------------------------------------------------------------
%% cont_service
%%----------------------------------------------------------------------------

cont_service(State = #state{recv_server = Server,
                            header_length = Length}) ->
    gen_server:cast(Server, {read_next_payload, Length}),
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

handle_received_payload({error, Reason}, State) ->
    ?LogIt(handle_received_payload, 
           "Error: ~p received while retrieving header. Exiting.",
           [Reason]),
    EState = exit_service(State),
    {noreply, EState};
handle_received_payload({ok, RawHeader},
                        State = #state{xdr_codecs = Codecs,
                                       xdr_args_map = XdrMap,
                                       io = Io}) ->
    % GDEBUG
    %?LogIt(handle_received_payload, "RawHeader: ~p.", [RawHeader]),
    case decode_header_and_type(RawHeader, State) of
        {{ok, {Type, Header}}, NState} ->
            case maps:find(Type, XdrMap) of
                {ok, XdrCallArgs} ->
                    CallArgs = XdrCallArgs#call_args{codec_env = Codecs},
                    % Allow errors to flow to next stage in pipe. REVISIT
                    % Valid Result will be: {ok, ResultValue}
                    %     while error Result will be: {error, Reason}.
                    {{ok, Payload}, NIo} = 
                        pur_utls_xdr:decode_generic(CallArgs, Io),
                    IoState = NState#state{io = NIo},
                    FState = cont_service(IoState),
                    {reply, {ok, {Header, Payload}}, FState};
                error ->
                    ?LogIt(handle_received_payload, 
                           "Type: ~p not supported. Exiting",
                           [Type]),
                    EState = exit_service(State),
                    {noreply, EState}
            end;
        {{error, Reason}, NState} ->
            ?LogIt(handle_received_payload, 
                   "Problem returning type for reason: ~p. Exiting",
                   [Reason]),
            EState = exit_service(NState),
            {noreply, EState}
    end.

%%----------------------------------------------------------------------------
%% retrieve_type
%%----------------------------------------------------------------------------

decode_header_and_type(RawHeader, 
                       State = #state{header_decoder = DecodeHeaderAndType}) ->
    {DecodeHeaderAndType(RawHeader), State}.

%%----------------------------------------------------------------------------
%% retrieve_type_for_simple_header
%%----------------------------------------------------------------------------

% Pure function

retrieve_type_for_simple_header(RawType) ->
    case pur_utls_xdr:decode_uint(RawType, #call_args{}) of
        {Type, _} -> {ok, {Type, Type}};
        _ -> {error, "XDR uint decode problem"}
    end.
            

