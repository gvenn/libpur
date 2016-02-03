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

-module(raw_socket_inter).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% % Execute in top repo directory
%% % To build
%% rebar3 shell
%% cd(repl).
%% c("raw_socket_inter.erl").
%%
%% % On Server
%% rebar3 shell
%% cd(repl).
%% l(raw_socket_inter).
%% f().
%% Port = 10000.
%% Options = [binary, {packet, raw}, {active, false}].
%% Socket = raw_socket_inter:server_start(Port, Options).
%% raw_socket_inter:server_receive(4, Socket).
%%
%% % On Client
%% rebar3 shell
%% cd(repl).
%% l(raw_socket_inter).
%% f().
%% Port = 10000.
%% Options = [binary, {packet, raw}, {active, false}].
%% Socket = raw_socket_inter:connect_client(localhost, Port, Options).
%% Data = raw_socket_inter:encode_struct().
%% raw_socket_inter:client_send(Data, Socket).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-include_lib("../include/pur_utls_xdr.hrl").

-export([server_start/2, server_receive/2, 
         connect_client/3, client_send/2, encode_struct/0, decode_struct/1]).

server_start(Port, Options) ->
    {ok, ListenSocket} = gen_tcp:listen(Port, Options),
    {ok, Socket} = gen_tcp:accept(ListenSocket),
    Socket.

server_receive(Length, Socket) ->
    {ok, LengthPacket} = gen_tcp:recv(Socket, Length),
    <<PayloadLength:32/integer>> = LengthPacket,
    {ok, PayloadPacket} = gen_tcp:recv(Socket, PayloadLength),
    decode_struct(PayloadPacket).

connect_client(Addr, Port, Options) ->
    {ok, Socket} = gen_tcp:connect(Addr, Port, Options),
    Socket.

client_send(Data, Socket) when is_binary(Data) ->
    M = pur_utls_xdr,
    Codecs = M:build_codecs(),
    CallArgs = #call_args{codec_env = Codecs},
    NumBytes = byte_size(Data),
    NumBytesEncoded = M:encode_uint(NumBytes, CallArgs), 
    gen_tcp:send(Socket, NumBytesEncoded),
    gen_tcp:send(Socket, Data).
    
encode_struct() ->
    M = pur_utls_xdr,
    Codecs = M:build_codecs(),
    CallArgs = #call_args{codec_env = Codecs},
    InnerMetaData = 
        [#call_args{etype = int},
         #call_args{etype = string},
         #call_args{etype = variable_opaque, len = 4},
         #call_args{etype = fixed_opaque, len = 3}, 
         #call_args{etype = float},
         #call_args{etype = double},
         #call_args{etype = quad},
         #call_args{etype = {fixed_array, string}, len = 2},
         #call_args{etype = {variable_array, uint}, len = 5}],
    InnerData = [1, "one", [1, 2, 3, 4], [5, 6, 7],
                 3.5, 4.123456789, 6789123.123456789,
                 ["three", "four"], [8, 9, 10, 11, 12]],
    UnionEnvData =
        #{1 => #call_args{etype = int},
          2 => #call_args{etype = string},
          3 => #call_args{etype = variable_opaque},
          4 => #call_args{etype = fixed_opaque, len = 3},
          5 => #call_args{etype = float},
          6 => #call_args{etype = double},
          7 => #call_args{etype = quad},
          8 => #call_args{etype = {fixed_array, string}, len = 2},
          9 => #call_args{etype = {variable_array, uint}},
          10 => #call_args{etype = struct, call_args = InnerMetaData}},
    %%%%%
    % Union Data
    %   [1, "one", [1, 2, 3, 4], [5, 6, 7],
    %    3.5, 4.123456789, 6789123.123456789,
    %    ["three", "four"], [8, 9, 10, 11, 12]],
    %%%%%
    OuterMetaData = 
        [#call_args{etype = string},
         #call_args{etype = union, env = UnionEnvData},
         #call_args{etype = string}],
    OuterData = ["begin", {10, InnerData}, "end"],
    M:encode_struct(
        OuterData, 
        CallArgs#call_args{
            call_args = OuterMetaData}).

decode_struct(Data) ->
    M = pur_utls_xdr,
    Codecs = M:build_codecs(),
    CallArgs = #call_args{codec_env = Codecs},
    InnerMetaData = 
        [#call_args{etype = int},
         #call_args{etype = string},
         #call_args{etype = variable_opaque, len = 4},
         #call_args{etype = fixed_opaque, len = 3}, 
         #call_args{etype = float},
         #call_args{etype = double},
         #call_args{etype = quad},
         #call_args{etype = {fixed_array, string}, len = 2},
         #call_args{etype = {variable_array, uint}, len = 5}],
    UnionEnvData =
        #{1 => #call_args{etype = int},
          2 => #call_args{etype = string},
          3 => #call_args{etype = variable_opaque},
          4 => #call_args{etype = fixed_opaque, len = 3},
          5 => #call_args{etype = float},
          6 => #call_args{etype = double},
          7 => #call_args{etype = quad},
          8 => #call_args{etype = {fixed_array, string}, len = 2},
          9 => #call_args{etype = {variable_array, uint}},
          10 => #call_args{etype = struct, call_args = InnerMetaData}},
    %%%%%
    % Union Data
    %   [1, "one", [1, 2, 3, 4], [5, 6, 7],
    %    3.5, 4.123456789, 6789123.123456789,
    %    ["three", "four"], [8, 9, 10, 11, 12]],
    %%%%%
    OuterMetaData = 
        [#call_args{etype = string},
         #call_args{etype = union, env = UnionEnvData},
         #call_args{etype = string}],
    M:decode_struct(Data, CallArgs#call_args{call_args = OuterMetaData}).
    
