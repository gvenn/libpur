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

-module(pur_utls_xdr_tests).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-include_lib("pur_utls_xdr.hrl").

scalar_test_() ->
    PX = pur_utls_xdr,
    CallArgs = #call_args{},
    [?_assert(42 =:= 
              element(1, PX:decode_int(PX:encode_int(42, CallArgs), 
                                       CallArgs))),
     ?_assert(4294967254 =:= 
              element(1, PX:decode_uint(PX:encode_uint(-42, CallArgs), 
                                        CallArgs))),
     ?_assert(-42 =:= 
              element(1, PX:decode_int(PX:encode_int(4294967254, CallArgs), 
                                       CallArgs))),
     ?_assert(-0.15625 =:= 
              element(1, PX:decode_quad(PX:encode_quad(-0.15625, CallArgs), 
                                        CallArgs))),
     ?_assert(-1.5625e-31 =:= 
              element(1, 
                      PX:decode_quad(PX:encode_quad(-1.5625e-31, CallArgs), 
                                     CallArgs))),
     % Notice data loss
     ?_assert(-1.56256789973476e-31 =:= 
              element(1, 
                      PX:decode_quad(
                          PX:encode_quad(
                              -1.562567899734759832178982376492659372e-31,
                              CallArgs), 
                          CallArgs)))].

io_scalar_test_() ->
    PX = pur_utls_xdr,
    CallArgs = #call_args{},
    Stream = <<>>,
    ReadFun = fun (Size, Io) -> 
                  % GDEBUG
                  %?LogIt(io_scalar_test_, "Io = ~p.", [Io]),
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
    {ok, Io1} = PX:encode_int(42, CallArgs, IoFuns),
    {ok, Io2} = PX:encode_uint(-42, CallArgs, Io1),
    {ok, Io3} = PX:encode_int(4294967254, CallArgs, Io2),
    {ok, Io4} = PX:encode_quad(-0.15625, CallArgs, Io3),
    {ok, Io5} = PX:encode_quad(-1.5625e-31, CallArgs, Io4),
    {ok, Io6} = PX:encode_quad(-1.562567899734759832178982376492659372e-31, 
                               CallArgs, 
                               Io5),
    {{ok, R1}, Io7} = PX:decode_int(CallArgs, Io6),
    {{ok, R2}, Io8} = PX:decode_uint(CallArgs, Io7),
    {{ok, R3}, Io9} = PX:decode_int(CallArgs, Io8),
    {{ok, R4}, Io10} = PX:decode_quad(CallArgs, Io9),
    {{ok, R5}, Io11} = PX:decode_quad(CallArgs, Io10),
    {{ok, R6}, _Io12} = PX:decode_quad(CallArgs, Io11),
    % GDEBUG
    %?LogIt(io_scalar_test_, "R1: ~p.", [R1]),
    [?_assert(42 =:= R1),
     ?_assert(4294967254 =:= R2),
     ?_assert(-42 =:= R3),
     ?_assert(-0.15625 =:= R4),
     ?_assert(-1.5625e-31 =:= R5),
     % Notice data loss
     ?_assert(-1.56256789973476e-31 =:= R6)].

generic_scalar_test_() ->
    PX = pur_utls_xdr,
    Codecs = PX:build_codecs(),
    CallArgs = #call_args{codec_env = Codecs},
    [?_assert(42 =:= 
              element(1, PX:decode_generic(
                             PX:encode_generic(
                                 42, 
                                 CallArgs#call_args{etype = int}), 
                             CallArgs#call_args{etype = int}))),
     ?_assert(4294967254 =:= 
              element(1, PX:decode_generic(
                             PX:encode_generic(
                                 -42, 
                                 CallArgs#call_args{etype = uint}), 
                             CallArgs#call_args{etype = uint}))),
     ?_assert(-42 =:= 
              element(1, PX:decode_generic(
                             PX:encode_generic(
                                 4294967254, 
                                 CallArgs#call_args{etype = int}), 
                             CallArgs#call_args{etype = int}))),
     ?_assert(-0.15625 =:= 
              element(1, PX:decode_generic(
                             PX:encode_generic(
                                 -0.15625, 
                                 CallArgs#call_args{etype = quad}), 
                             CallArgs#call_args{etype = quad}))),
     ?_assert(-1.5625e-31 =:= 
              element(1, 
                      PX:decode_generic(
                          PX:encode_generic(
                              -1.5625e-31, 
                              CallArgs#call_args{etype = quad}), 
                          CallArgs#call_args{etype = quad}))),
     % Notice data loss
     ?_assert(-1.56256789973476e-31 =:= 
              element(1, 
                      PX:decode_generic(
                          PX:encode_generic(
                              -1.562567899734759832178982376492659372e-31,
                              CallArgs#call_args{etype = quad}), 
                          CallArgs#call_args{etype = quad})))].

generic_io_scalar_test_() ->
    PX = pur_utls_xdr,
    Codecs = PX:build_codecs(),
    CallArgs = #call_args{codec_env = Codecs},
    Stream = <<>>,
    ReadFun = fun (Size, Io) -> 
                  % GDEBUG
                  %?LogIt(io_scalar_test_, "Io = ~p.", [Io]),
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
    {ok, Io1} = PX:encode_generic(42, 
                                  CallArgs#call_args{etype = int}, 
                                  IoFuns),
    {ok, Io2} = PX:encode_generic(-42, 
                                  CallArgs#call_args{etype = uint}, 
                                  Io1),
    {ok, Io3} = PX:encode_generic(4294967254, 
                                  CallArgs#call_args{etype = int}, 
                                  Io2),
    {ok, Io4} = PX:encode_generic(-0.15625, 
                                  CallArgs#call_args{etype = quad}, 
                                  Io3),
    {ok, Io5} = PX:encode_generic(-1.5625e-31, 
                                  CallArgs#call_args{etype = quad}, 
                                  Io4),
    {ok, Io6} = PX:encode_generic(-1.562567899734759832178982376492659372e-31, 
                                  CallArgs#call_args{etype = quad}, 
                                  Io5),
    {{ok, R1}, Io7} = PX:decode_generic(CallArgs#call_args{etype = int}, 
                                        Io6),
    {{ok, R2}, Io8} = PX:decode_generic(CallArgs#call_args{etype = uint}, 
                                        Io7),
    {{ok, R3}, Io9} = PX:decode_generic(CallArgs#call_args{etype = int}, 
                                        Io8),
    {{ok, R4}, Io10} = PX:decode_generic(CallArgs#call_args{etype = quad}, 
                                         Io9),
    {{ok, R5}, Io11} = PX:decode_generic(CallArgs#call_args{etype = quad}, 
                                         Io10),
    {{ok, R6}, _Io12} = PX:decode_generic(CallArgs#call_args{etype = quad}, 
                                          Io11),
    % GDEBUG
    %?LogIt(io_scalar_test_, "R1: ~p.", [R1]),
    [?_assert(42 =:= R1),
     ?_assert(4294967254 =:= R2),
     ?_assert(-42 =:= R3),
     ?_assert(-0.15625 =:= R4),
     ?_assert(-1.5625e-31 =:= R5),
     % Notice data loss
     ?_assert(-1.56256789973476e-31 =:= R6)].

fixed_vector_test_() ->
    E = fun (Expr) -> element(1, Expr) end,
    M = pur_utls_xdr,
    Codecs = M:build_codecs(),
    Data = ["one","two","three","four"],
    CallArgs = #call_args{codec_env = Codecs},
    [?_assert(Data =:=
                  E(M:decode_fixed_array(
                        M:encode_fixed_array(
                            Data, 
                            CallArgs#call_args{len = 4, etype = string}), 
                    CallArgs#call_args{etype = string}))),
     ?_assert(["one","two","three"] =:=
                  E(M:decode_fixed_array(
                        M:encode_fixed_array(
                            Data, 
                            CallArgs#call_args{len = 3, etype = string}), 
                    CallArgs#call_args{etype = string}))),
     ?_assert(Data =:=
                  E(M:decode_fixed_array(
                        M:encode_fixed_array(
                            Data, 
                            CallArgs#call_args{len = 5, etype = string}), 
                    CallArgs#call_args{etype = string})))].

fixed_io_vector_test_() ->
    PX = pur_utls_xdr,
    Codecs = PX:build_codecs(),
    Data = ["one","two","three","four"],
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
    {ok, Io1} = PX:encode_fixed_array(
                    Data, 
                    CallArgs#call_args{len = 4, etype = string}, 
                    IoFuns),
    {ok, Io2} = PX:encode_fixed_array(
                    Data, 
                    CallArgs#call_args{len = 3, etype = string}, 
                    Io1),
    {ok, Io3} = PX:encode_fixed_array(
                    Data, 
                    % Encoding will only see 4 elements, and will ignore
                    %     rest of length
                    CallArgs#call_args{len = 5, etype = string}, 
                    Io2),
    {{ok, R1}, Io4} = PX:decode_fixed_array(
                          CallArgs#call_args{len = 4, etype = string}, 
                          Io3),
    {{ok, R2}, Io5} = PX:decode_fixed_array(
                          CallArgs#call_args{len = 3, etype = string}, 
                          Io4),
    {{ok, R3}, _Io6} = PX:decode_fixed_array(
                           % Decoding must be given true length, even though
                           %    encoding can handle false lengths.
                           CallArgs#call_args{len = 4, etype = string}, 
                           Io5),
    [?_assert(Data =:= R1),
     ?_assert(["one","two","three"] =:= R2),
     ?_assert(Data =:= R3)].

generic_fixed_vector_test_() ->
    E = fun (Expr) -> element(1, Expr) end,
    M = pur_utls_xdr,
    Codecs = M:build_codecs(),
    Data = ["one","two","three","four"],
    CallArgs = #call_args{codec_env = Codecs},
    [?_assert(Data =:=
                  E(M:decode_generic(
                        M:encode_generic(
                            Data, 
                            CallArgs#call_args{
                                len = 4, 
                                etype = {fixed_array, string}}), 
                    CallArgs#call_args{etype = {fixed_array, string}}))),
     ?_assert(["one","two","three"] =:=
                  E(M:decode_generic(
                        M:encode_generic(
                            Data, 
                            CallArgs#call_args{
                                len = 3, 
                                etype = {fixed_array, string}}), 
                    CallArgs#call_args{etype = {fixed_array, string}}))),
     ?_assert(Data =:=
                  E(M:decode_generic(
                        M:encode_generic(
                            Data, 
                            CallArgs#call_args{
                                len = 5, 
                                etype = {fixed_array, string}}), 
                    CallArgs#call_args{etype = {fixed_array, string}})))].

generic_fixed_io_vector_test_() ->
    PX = pur_utls_xdr,
    Codecs = PX:build_codecs(),
    Data = ["one","two","three","four"],
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
    {ok, Io1} = PX:encode_generic(
                    Data, 
                    CallArgs#call_args{len = 4, 
                                       etype = {fixed_array, string}}, 
                    IoFuns),
    {ok, Io2} = PX:encode_generic(
                    Data, 
                    CallArgs#call_args{len = 3, 
                                       etype = {fixed_array, string}}, 
                    Io1),
    {ok, Io3} = PX:encode_generic(
                    Data, 
                    % Encoding will only see 4 elements, and will ignore
                    %     rest of length
                    CallArgs#call_args{len = 5, 
                                       etype = {fixed_array, string}}, 
                    Io2),
    {{ok, R1}, Io4} = PX:decode_generic(
                          CallArgs#call_args{len = 4, 
                                             etype = {fixed_array, string}}, 
                          Io3),
    {{ok, R2}, Io5} = PX:decode_generic(
                          CallArgs#call_args{len = 3, 
                                             etype = {fixed_array, string}}, 
                          Io4),
    {{ok, R3}, _Io6} = PX:decode_generic(
                           % Decoding must be given true length, even though
                           %    encoding can handle false lengths.
                           CallArgs#call_args{len = 4, 
                                              etype = {fixed_array, string}}, 
                           Io5),
    [?_assert(Data =:= R1),
     ?_assert(["one","two","three"] =:= R2),
     ?_assert(Data =:= R3)].

variable_vector_test_() ->
    E = fun (Expr) -> element(1, Expr) end,
    M = pur_utls_xdr,
    Codecs = M:build_codecs(),
    CallArgs = #call_args{codec_env = Codecs},
    IntData = lists:seq(1,3),
    StringData = ["one","two","three","four"],
    [?_assert([1,2] =:= 
                  E(M:decode_variable_array(
                        M:encode_variable_array(
                            IntData, 
                            CallArgs#call_args{len = 2, etype = int}),
                        CallArgs#call_args{etype = int}))),
     ?_assert(StringData =:= 
                  E(M:decode_variable_array(
                        M:encode_variable_array(
                            StringData, 
                            CallArgs#call_args{len = 4, etype = string}),
                        CallArgs#call_args{etype = string}))),
     ?_assert(["one","two","three"] =:= 
                  E(M:decode_variable_array(
                        M:encode_variable_array(
                            StringData, 
                            CallArgs#call_args{len = 3, etype = string}),
                        CallArgs#call_args{etype = string}))),
     ?_assert(StringData =:= 
                  E(M:decode_variable_array(
                        M:encode_variable_array(
                            StringData, 
                            CallArgs#call_args{len = 5, etype = string}),
                        CallArgs#call_args{etype = string})))].

variable_io_vector_test_() ->
    PX = pur_utls_xdr,
    Codecs = PX:build_codecs(),
    Data = ["one","two","three","four"],
    IntData = lists:seq(1,3),
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
    {ok, Io1} = PX:encode_variable_array(
                    IntData, 
                    CallArgs#call_args{len = 2, etype = int}, 
                    IoFuns),
    {ok, Io2} = PX:encode_variable_array(
                    Data, 
                    CallArgs#call_args{len = 4, etype = string}, 
                    Io1),
    {ok, Io3} = PX:encode_variable_array(
                    Data, 
                    CallArgs#call_args{len = 3, etype = string}, 
                    Io2),
    {ok, Io4} = PX:encode_variable_array(
                    Data, 
                    % Encoding will only see 4 elements, and will ignore
                    %     rest of length
                    CallArgs#call_args{len = 5, etype = string}, 
                    Io3),
    {{ok, R1}, Io5} = PX:decode_variable_array(
                          CallArgs#call_args{etype = int}, 
                          Io4),
    {{ok, R2}, Io6} = PX:decode_variable_array(
                          CallArgs#call_args{etype = string}, 
                          Io5),
    {{ok, R3}, Io7} = PX:decode_variable_array(
                          CallArgs#call_args{etype = string}, 
                          Io6),
    {{ok, R4}, _Io8} = PX:decode_variable_array(
                           CallArgs#call_args{etype = string}, 
                           Io7),
    [?_assert([1,2] =:= R1),
     ?_assert(Data =:= R2),
     ?_assert(["one","two","three"] =:= R3),
     ?_assert(Data =:= R4)].

generic_variable_vector_test_() ->
    E = fun (Expr) -> element(1, Expr) end,
    M = pur_utls_xdr,
    Codecs = M:build_codecs(),
    CallArgs = #call_args{codec_env = Codecs},
    IntData = lists:seq(1,3),
    StringData = ["one","two","three","four"],
    [?_assert([1,2] =:= 
                  E(M:decode_generic(
                        M:encode_generic(
                            IntData, 
                            CallArgs#call_args{
                                len = 2, 
                                etype = {variable_array, int}}),
                        CallArgs#call_args{
                            etype = {variable_array, int}}))),
     ?_assert(StringData =:= 
                  E(M:decode_generic(
                        M:encode_generic(
                            StringData, 
                            CallArgs#call_args{
                                len = 4, 
                                etype = {variable_array, string}}),
                        CallArgs#call_args{
                            etype = {variable_array, string}}))),
     ?_assert(["one","two","three"] =:= 
                  E(M:decode_generic(
                        M:encode_generic(
                            StringData, 
                            CallArgs#call_args{
                                len = 3, 
                                etype = {variable_array, string}}),
                        CallArgs#call_args{
                            etype = {variable_array, string}}))),
     ?_assert(StringData =:= 
                  E(M:decode_generic(
                        M:encode_generic(
                            StringData, 
                            CallArgs#call_args{
                                len = 5, 
                                etype = {variable_array, string}}),
                        CallArgs#call_args{
                            etype = {variable_array, string}})))].

generic_variable_io_vector_test_() ->
    PX = pur_utls_xdr,
    Codecs = PX:build_codecs(),
    Data = ["one","two","three","four"],
    IntData = lists:seq(1,3),
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
    {ok, Io1} = PX:encode_generic(
                    IntData, 
                    CallArgs#call_args{len = 2, 
                                       etype = {variable_array, int}}, 
                    IoFuns),
    {ok, Io2} = PX:encode_generic(
                    Data, 
                    CallArgs#call_args{len = 4, 
                                       etype = {variable_array, string}}, 
                    Io1),
    {ok, Io3} = PX:encode_generic(
                    Data, 
                    CallArgs#call_args{len = 3, 
                                       etype = {variable_array, string}}, 
                    Io2),
    {ok, Io4} = PX:encode_generic(
                    Data, 
                    % Encoding will only see 4 elements, and will ignore
                    %     rest of length
                    CallArgs#call_args{len = 5, 
                                       etype = {variable_array, string}}, 
                    Io3),
    {{ok, R1}, Io5} = PX:decode_generic(
                          CallArgs#call_args{etype = {variable_array, int}}, 
                          Io4),
    {{ok, R2}, Io6} = PX:decode_generic(
                          CallArgs#call_args{etype = 
                                                 {variable_array, string}}, 
                          Io5),
    {{ok, R3}, Io7} = PX:decode_generic(
                          CallArgs#call_args{etype = 
                                                 {variable_array, string}}, 
                          Io6),
    {{ok, R4}, _Io8} = PX:decode_generic(
                           CallArgs#call_args{etype = 
                                                 {variable_array, string}}, 
                           Io7),
    [?_assert([1,2] =:= R1),
     ?_assert(Data =:= R2),
     ?_assert(["one","two","three"] =:= R3),
     ?_assert(Data =:= R4)].

struct_test_() ->
    E = fun (Expr) -> element(1, Expr) end,
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
    OuterMetaData = 
        [#call_args{etype = string},
         #call_args{etype = struct, call_args = InnerMetaData},
         #call_args{etype = string}],
    OuterData = ["begin", InnerData, "end"],
    [?_assert(InnerData =:= 
                  E(M:decode_struct(
                        M:encode_struct(
                            InnerData, 
                            CallArgs#call_args{
                                call_args = InnerMetaData}),
                        CallArgs#call_args{call_args = 
                            InnerMetaData}))),
     ?_assert(OuterData =:= 
                  E(M:decode_struct(
                        M:encode_struct(
                            OuterData, 
                            CallArgs#call_args{
                                call_args = OuterMetaData}),
                        CallArgs#call_args{call_args = 
                            OuterMetaData})))].

struct_io_test_() ->
    PX = pur_utls_xdr,
    Codecs = PX:build_codecs(),
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
    OuterMetaData = 
        [#call_args{etype = string},
         #call_args{etype = struct, call_args = InnerMetaData},
         #call_args{etype = string}],
    OuterData = ["begin", InnerData, "end"],
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
    {ok, Io1} = PX:encode_struct(
                    InnerData, 
                    CallArgs#call_args{call_args = InnerMetaData},
                    IoFuns),
    {ok, Io2} = PX:encode_struct(
                    OuterData, 
                    CallArgs#call_args{call_args = OuterMetaData},
                    Io1),
    {{ok, R1}, Io3} = PX:decode_struct(
                          CallArgs#call_args{call_args = InnerMetaData},
                          Io2),
    {{ok, R2}, _Io4} = PX:decode_struct(
                           CallArgs#call_args{call_args = OuterMetaData},
                           Io3),
    [?_assert(InnerData =:= R1),
     ?_assert(OuterData =:= R2)].

generic_struct_test_() ->
    E = fun (Expr) -> element(1, Expr) end,
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
    OuterMetaData = 
        [#call_args{etype = string},
         #call_args{etype = struct, call_args = InnerMetaData},
         #call_args{etype = string}],
    OuterData = ["begin", InnerData, "end"],
    [?_assert(InnerData =:= 
                  E(M:decode_generic(
                        M:encode_generic(
                            InnerData, 
                            CallArgs#call_args{
                                etype = struct,
                                call_args = InnerMetaData}),
                        CallArgs#call_args{etype = struct,
                                           call_args = InnerMetaData}))),
     ?_assert(OuterData =:= 
                  E(M:decode_generic(
                        M:encode_generic(
                            OuterData, 
                            CallArgs#call_args{
                                etype = struct,
                                call_args = OuterMetaData}),
                        CallArgs#call_args{etype = struct,
                                           call_args = OuterMetaData})))].

generic_struct_io_test_() ->
    PX = pur_utls_xdr,
    Codecs = PX:build_codecs(),
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
    OuterMetaData = 
        [#call_args{etype = string},
         #call_args{etype = struct, call_args = InnerMetaData},
         #call_args{etype = string}],
    OuterData = ["begin", InnerData, "end"],
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
    {ok, Io1} = PX:encode_generic(
                    InnerData, 
                    CallArgs#call_args{etype = struct,
                                       call_args = InnerMetaData},
                    IoFuns),
    {ok, Io2} = PX:encode_generic(
                    OuterData, 
                    CallArgs#call_args{etype = struct,
                                       call_args = OuterMetaData},
                    Io1),
    {{ok, R1}, Io3} = PX:decode_generic(
                          CallArgs#call_args{etype = struct,
                                             call_args = InnerMetaData},
                          Io2),
    {{ok, R2}, _Io4} = PX:decode_generic(
                           CallArgs#call_args{etype = struct,
                                              call_args = OuterMetaData},
                           Io3),
    [?_assert(InnerData =:= R1),
     ?_assert(OuterData =:= R2)].

union_test_() ->
    E = fun (Expr) -> element(1, Expr) end,
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
    TestData = ["begin", InnerData, "end"],
    [?_assert(4.123456789 =:= 
                  E(M:decode_union(
                        M:encode_union(
                            {6, 4.123456789}, 
                            CallArgs#call_args{env = UnionEnvData}),
                        CallArgs#call_args{env = UnionEnvData}))),
     ?_assert(TestData =:= 
                  E(M:decode_struct(
                        M:encode_struct(
                            OuterData, 
                            CallArgs#call_args{
                                call_args = OuterMetaData}),
                        CallArgs#call_args{call_args = OuterMetaData}))),
     ?_assert("one" =:= 
                  E(M:decode_optional(
                        M:encode_optional(
                            {true, "one"}, 
                            CallArgs#call_args{etype = string}),
                        CallArgs#call_args{etype = string}))),
     ?_assert([] =:= 
                  E(M:decode_optional(
                        M:encode_optional(
                            {false, "one"}, 
                            CallArgs#call_args{etype = string}),
                        CallArgs#call_args{etype = string})))].

union_io_test_() ->
    PX = pur_utls_xdr,
    Codecs = PX:build_codecs(),
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
    TestData = ["begin", InnerData, "end"],
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
    {ok, Io1} = PX:encode_union(
                    {6, 4.123456789}, 
                    CallArgs#call_args{env = UnionEnvData},
                    IoFuns),
    {ok, Io2} = PX:encode_struct(
                    OuterData, 
                    CallArgs#call_args{call_args = OuterMetaData},
                    Io1),
    {ok, Io3} = PX:encode_optional(
                    {true, "one"}, 
                    CallArgs#call_args{etype = string},
                    Io2),
    {ok, Io4} = PX:encode_optional(
                    {false, "one"}, 
                    CallArgs#call_args{etype = string},
                    Io3),
    {{ok, R1}, Io5} = PX:decode_union(
                          CallArgs#call_args{env = UnionEnvData},
                          Io4),
    {{ok, R2}, Io6} = PX:decode_struct(
                          CallArgs#call_args{call_args = OuterMetaData},
                          Io5),
    {{ok, R3}, Io7} = PX:decode_optional(
                          CallArgs#call_args{etype = string},
                          Io6),
    {{ok, R4}, _Io8} = PX:decode_optional(
                           CallArgs#call_args{etype = string},
                           Io7),
    [?_assert(4.123456789 =:= R1),
     ?_assert(TestData =:= R2),
     ?_assert("one" =:= R3),
     ?_assert([] =:= R4)].

generic_union_test_() ->
    E = fun (Expr) -> element(1, Expr) end,
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
    TestData = ["begin", InnerData, "end"],
    [?_assert(4.123456789 =:= 
                  E(M:decode_generic(
                        M:encode_generic(
                            {6, 4.123456789}, 
                            CallArgs#call_args{etype = union,
                                               env = UnionEnvData}),
                        CallArgs#call_args{etype = union,
                                           env = UnionEnvData}))),
     ?_assert(TestData =:= 
                  E(M:decode_generic(
                        M:encode_generic(
                            OuterData, 
                            CallArgs#call_args{
                                etype = struct,
                                call_args = OuterMetaData}),
                        CallArgs#call_args{etype = struct,
                                           call_args = OuterMetaData}))),
     ?_assert("one" =:= 
                  E(M:decode_generic(
                        M:encode_generic(
                            {true, "one"}, 
                            CallArgs#call_args{etype = {optional, string}}),
                        CallArgs#call_args{etype = {optional, string}}))),
     ?_assert([] =:= 
                  E(M:decode_generic(
                        M:encode_generic(
                            {false, "one"}, 
                            CallArgs#call_args{etype = {optional, string}}),
                        CallArgs#call_args{etype = {optional, string}})))].

generic_union_io_test_() ->
    PX = pur_utls_xdr,
    Codecs = PX:build_codecs(),
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
    TestData = ["begin", InnerData, "end"],
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
    {ok, Io1} = PX:encode_generic(
                    {6, 4.123456789}, 
                    CallArgs#call_args{etype = union, env = UnionEnvData},
                    IoFuns),
    {ok, Io2} = PX:encode_generic(
                    OuterData, 
                    CallArgs#call_args{etype = struct, 
                                       call_args = OuterMetaData},
                    Io1),
    {ok, Io3} = PX:encode_generic(
                    {true, "one"}, 
                    CallArgs#call_args{etype = {optional, string}},
                    Io2),
    {ok, Io4} = PX:encode_generic(
                    {false, "one"}, 
                    CallArgs#call_args{etype = {optional, string}},
                    Io3),
    {{ok, R1}, Io5} = PX:decode_generic(
                          CallArgs#call_args{etype = union, 
                                             env = UnionEnvData},
                          Io4),
    {{ok, R2}, Io6} = PX:decode_generic(
                          CallArgs#call_args{etype = struct,
                                             call_args = OuterMetaData},
                          Io5),
    {{ok, R3}, Io7} = PX:decode_generic(
                          CallArgs#call_args{etype = {optional, string}},
                          Io6),
    {{ok, R4}, _Io8} = PX:decode_generic(
                           CallArgs#call_args{etype = {optional, string}},
                           Io7),
    [?_assert(4.123456789 =:= R1),
     ?_assert(TestData =:= R2),
     ?_assert("one" =:= R3),
     ?_assert([] =:= R4)].
-endif.

