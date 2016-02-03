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

-module(xdr_inter).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% % Execute in top repo directory
%% % To build
%% rebar3 shell
%% cd(repl).
%% c("xdr_inter.erl").
%% f().
%% xdr_inter:send_and_receive_string("hello").
%% xdr_inter:send_and_receive_strings(["one", "two"]).
%% xdr_inter:send_and_receive_list(string, ["one", "two"]).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-export([send_and_receive_string/1, send_and_receive_strings/1, 
         send_and_receive_list/2]).

-include_lib("../include/pur_utls_xdr.hrl").

send_and_receive_string(String) ->   
    PX = pur_utls_xdr,
    Codecs = PX:build_codecs(),
    CallArgs = #call_args{codec_env = Codecs},
    Stream = <<>>,
    ReadFun = fun (Size, Io) -> 
                  BitSize = Size bsl 3,
                  <<Ret:BitSize/bitstring, Rest/bitstring>> = Io,
                  {{ok, Ret}, Rest}
              end,
    WriteFun = fun (Size, Value, Io) -> 
                  BitSize = Size bsl 3,
                   NIo = <<Io/bitstring, Value:BitSize/bitstring>>,
                   {ok, NIo}
               end,
    IoFuns = #io_funs{context = Stream,
                      read_fun = ReadFun,
                      write_fun = WriteFun},
    {ok, Io1} = PX:encode_string(String, CallArgs, IoFuns),
    {{ok, Result}, _Io2} = PX:decode_string(CallArgs, Io1),
    Result.

send_and_receive_strings(Strings) when is_list(Strings) ->   
    PX = pur_utls_xdr,
    Codecs = PX:build_codecs(),
    CallArgs = #call_args{codec_env = Codecs},
    Stream = <<>>,
    ReadFun = fun (Size, Io) -> 
                  BitSize = Size bsl 3,
                  <<Ret:BitSize/bitstring, Rest/bitstring>> = Io,
                  {{ok, Ret}, Rest}
              end,
    WriteFun = fun (Size, Value, Io) -> 
                  BitSize = Size bsl 3,
                   NIo = <<Io/bitstring, Value:BitSize/bitstring>>,
                   {ok, NIo}
               end,
    IoFuns = #io_funs{context = Stream,
                      read_fun = ReadFun,
                      write_fun = WriteFun},
    {_, EIoFuns} =
        lists:foldl(
            fun (NextString, {_, NIo}) ->
                PX:encode_string(NextString, CallArgs, NIo)
            end,
            {ok, IoFuns},
            Strings),
    {{ok, Results}, _} =
        pur_utls_misc:iterate(length(Strings),
                              {{ok, []}, EIoFuns},
                              fun (_Count, {{ok, Acc}, NIo}) ->
                                  {{ok, NResult}, NNIo} =
                                      PX:decode_string(CallArgs, NIo),
                                  {true, {{ok, [NResult|Acc]}, NNIo}}
                              end),
    lists:reverse(Results).

send_and_receive_list(Type, Data) when is_list(Data) ->   
    PX = pur_utls_xdr,
    Codecs = PX:build_codecs(),
    CallArgs = #call_args{etype = Type, codec_env = Codecs},
    Stream = <<>>,
    ReadFun = fun (Size, Io) -> 
                  BitSize = Size bsl 3,
                  <<Ret:BitSize/bitstring, Rest/bitstring>> = Io,
                  {{ok, Ret}, Rest}
              end,
    WriteFun = fun (Size, Value, Io) -> 
                  BitSize = Size bsl 3,
                   NIo = <<Io/bitstring, Value:BitSize/bitstring>>,
                   {ok, NIo}
               end,
    IoFuns = #io_funs{context = Stream,
                      read_fun = ReadFun,
                      write_fun = WriteFun},
    {ok, Io1} = PX:encode_fixed_array(Data, CallArgs, IoFuns),
    {{ok, Result}, _Io2} = PX:decode_fixed_array(
                               CallArgs#call_args{len = length(Data)}, 
                               Io1),
    Result.
