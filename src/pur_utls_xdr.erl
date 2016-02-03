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

-module(pur_utls_xdr).

-export([build_codecs/0, encode_int/2, encode_int/3, decode_int/2, 
         encode_uint/2, encode_uint/3, decode_uint/2, 
         encode_hyper_int/2, encode_hyper_int/3, decode_hyper_int/2, 
         encode_hyper_uint/2, encode_hyper_uint/3, decode_hyper_uint/2, 
         encode_float/2, encode_float/3, decode_float/2, 
         encode_double/2, encode_double/3, decode_double/2,
         encode_quad/2, encode_quad/3, decode_quad/2,
         encode_fixed_opaque/2, encode_fixed_opaque/3, decode_fixed_opaque/2,
         encode_variable_opaque/2, 
         encode_variable_opaque/3, decode_variable_opaque/2,
         encode_string/2, encode_string/3, decode_string/2,
         encode_fixed_array/2, encode_fixed_array/3, decode_fixed_array/2,
         encode_variable_array/2, 
         encode_variable_array/3, decode_variable_array/2, 
         encode_struct/2, encode_struct/3, decode_struct/2,
         encode_union/2, encode_union/3, decode_union/2, 
         encode_void/0, encode_void/2, encode_void/3, decode_void/2,
         encode_optional/2, encode_optional/3, decode_optional/2,
         encode_generic/2, encode_generic/3, decode_generic/2]).

-include_lib("pur_utls_xdr.hrl").

% Arities cannot really be decoupled as it dependent on the callers.
-record(elem_config, {etype,
                      encode_arity = 2,
                      io_encode_arity = 3,
                      decode_arity = 2,
                      io_decode_arity = 2}).

% encode_generic/2, and decode_generic/2, are not included. REVISIT
-define(ElemTypes, [#elem_config{etype = int},
                    #elem_config{etype = uint},
                    #elem_config{etype = hyper_int},
                    #elem_config{etype = hyper_uint},
                    #elem_config{etype = float},
                    #elem_config{etype = double},
                    #elem_config{etype = quad},
                    #elem_config{etype = fixed_opaque},
                    #elem_config{etype = variable_opaque},
                    #elem_config{etype = string},
                    #elem_config{etype = fixed_array},
                    #elem_config{etype = variable_array},
                    #elem_config{etype = struct},
                    #elem_config{etype = union},
                    #elem_config{etype = void},
                    #elem_config{etype = optional}]).

-record(elem_funs, {encode, io_encode, decode, io_decode}).

-record(etype_codecs, {codecs}).

%%----------------------------------------------------------------------------
%% build_elem_types
%%----------------------------------------------------------------------------

build_elem_types() ->
    lists:map(
        fun (#elem_config{etype = Type, 
                          encode_arity = EArity, 
                          io_encode_arity = IoEArity,
                          decode_arity = DArity,
                          io_decode_arity = IoDArity}) ->
            % Will take a hit on execution since we are not constructing a
            %     Fun == encode_<name>/Arity. Look up will take place,
            %     the way we are using it which helps dynamic code reload.
            EncoderAtom = convert_to_atom("encode_" ++ atom_to_list(Type)),
            % Slower form with module specification. REVISIT
            Encoder = {EArity, fun ?MODULE:EncoderAtom/EArity},
            % Slower form with module specification. REVISIT
            IoEncoder = {IoEArity, fun ?MODULE:EncoderAtom/IoEArity},
            DecoderAtom = convert_to_atom("decode_" ++ atom_to_list(Type)),
            % Slower form with module specification. REVISIT
            Decoder = {DArity, fun ?MODULE:DecoderAtom/DArity},
            % Slower form with module specification. REVISIT
            IoDecoder = {IoDArity, fun ?MODULE:DecoderAtom/IoDArity},
            {Type, 
             #elem_funs{encode = Encoder,
                        io_encode = IoEncoder,
                        decode = Decoder,
                        io_decode = IoDecoder}}
        end,
        ?ElemTypes).

%%----------------------------------------------------------------------------
%% find_codecs
%%----------------------------------------------------------------------------

find_codecs(EType, #etype_codecs{codecs = Codecs}) ->
    case proplists:get_value(EType, Codecs) of
        R = #elem_funs{} -> R;
        _ -> undefined
    end.

%%----------------------------------------------------------------------------
%% find_all_codecs
%%----------------------------------------------------------------------------

-ifdef(Unused).
find_all_codecs(EType, #etype_codecs{codecs = Codecs}) ->
    case proplists:get_all_values(EType, Codecs) of
        [] -> undefined;
        R -> R
    end.
-endif.

%%----------------------------------------------------------------------------
%% find_coder_util
%%----------------------------------------------------------------------------

find_coder_util(EType, Index, CodecEnv = #etype_codecs{}) ->
    case find_codecs(EType, CodecEnv) of
        R = #elem_funs{} ->
            {_Arity, Result} = element(Index, R),
            Result;
        R -> R
    end.

%%----------------------------------------------------------------------------
%% find_encoder
%%----------------------------------------------------------------------------

find_encoder(EType, CodecEnv = #etype_codecs{}) ->
    find_coder_util(EType, #elem_funs.encode, CodecEnv).

%%----------------------------------------------------------------------------
%% find_io_encoder
%%----------------------------------------------------------------------------

-ifdef(Unused).
find_io_encoder(EType, CodecEnv = #etype_codecs{}) ->
    find_coder_util(EType, #elem_funs.io_encode, CodecEnv).
-endif.

%%----------------------------------------------------------------------------
%% find_all_encoders
%%----------------------------------------------------------------------------

-ifdef(Unused).
find_all_encoders(EType, CodecEnv = #etype_codecs{}) ->
    case find_all_codecs(EType, CodecEnv) of
        undefined -> undefined;
        R -> lists:map(fun (#elem_funs{encode = {Arity, Encoder}}) ->
                           {Arity, Encoder}
                       end,
                       R)
    end.
-endif.

%%----------------------------------------------------------------------------
%% find_decoder
%%----------------------------------------------------------------------------

find_decoder(EType, CodecEnv = #etype_codecs{}) ->
    find_coder_util(EType, #elem_funs.decode, CodecEnv).

%%----------------------------------------------------------------------------
%% find_io_decoder
%%----------------------------------------------------------------------------

find_io_decoder(EType, CodecEnv = #etype_codecs{}) ->
    find_coder_util(EType, #elem_funs.io_decode, CodecEnv).

%%----------------------------------------------------------------------------
%% find_all_decoders
%%----------------------------------------------------------------------------

-ifdef(Unused).
find_all_decoders(EType, CodecEnv = #etype_codecs{}) ->
    case find_all_codecs(EType, CodecEnv) of
        undefined -> undefined;
        R -> lists:map(fun (#elem_funs{decode = {Arity, Decoder}}) ->
                           {Arity, Decoder}
                       end,
                       R)
    end.
-endif.

%%----------------------------------------------------------------------------
%% convert_to_atom
%%----------------------------------------------------------------------------

convert_to_atom(List) when is_list(List) ->
    try
        list_to_existing_atom(List)
    catch
        _:_ -> list_to_atom(List)
    end.
                  
%%----------------------------------------------------------------------------
%% build_codecs
%%----------------------------------------------------------------------------

build_codecs() ->
    #etype_codecs{codecs = build_elem_types()}.

%%----------------------------------------------------------------------------
%% encode_int
%%----------------------------------------------------------------------------

encode_int(Value, _) when is_integer(Value) ->
    % Default is big, and uses twos complement
    <<Value:32/integer-signed>>.

encode_int(Value, _, State = #io_funs{context = Context, 
                                      write_fun = Fun}) 
        when is_integer(Value) ->
    % Default is big, and uses twos complement
    {Status, NContext} = Fun(4, <<Value:32/integer-signed>>, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_int
%%----------------------------------------------------------------------------

decode_int(<<Value:32/integer-signed, R/bitstring>>, #call_args{}) ->
    {Value, R};
decode_int(_, State = #io_funs{context = Context,
                               read_fun = Fun}) ->
    {FResult, FContext} =
        case Fun(4, Context) of
            {{ok, <<Value:32/integer-signed>>}, NContext} ->
                {{ok, Value}, NContext};
            {Result, NContext} ->
                {Result, NContext}
        end,
    {FResult, State#io_funs{context = FContext}}.
    
%%----------------------------------------------------------------------------
%% encode_uint
%%----------------------------------------------------------------------------

encode_uint(Value, _) when is_integer(Value) ->
    % Default is big.
    <<Value:32/integer-unsigned>>.

encode_uint(Value, _, State = #io_funs{context = Context, 
                                       write_fun = Fun}) 
        when is_integer(Value) ->
    % Default is big, and uses twos complement
    {Status, NContext} = Fun(4, <<Value:32/integer-unsigned>>, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_uint
%%----------------------------------------------------------------------------

decode_uint(<<Value:32/integer-unsigned, R/bitstring>>, _) ->
    {Value, R};
decode_uint(_, State = #io_funs{context = Context,
                                read_fun = Fun}) ->
    {FResult, FContext} =
        case Fun(4, Context) of
            {{ok, <<Value:32/integer-unsigned>>}, NContext} ->
                {{ok, Value}, NContext};
            {Result, NContext} ->
                {Result, NContext}
        end,
    {FResult, State#io_funs{context = FContext}}.

%%----------------------------------------------------------------------------
%% encode_hyper_int
%%----------------------------------------------------------------------------

encode_hyper_int(Value, _) when is_integer(Value) ->
    % Default is big, and uses twos complement
    <<Value:64/integer-signed>>.

encode_hyper_int(Value, _, State = #io_funs{context = Context, 
                                            write_fun = Fun}) 
        when is_integer(Value) ->
    % Default is big, and uses twos complement
    {Status, NContext} = Fun(8, <<Value:64/integer-signed>>, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_hyper_int
%%----------------------------------------------------------------------------

decode_hyper_int(<<Value:64/integer-signed, R/bitstring>>, _) ->
    {Value, R};
decode_hyper_int(_, State = #io_funs{context = Context,
                                     read_fun = Fun}) ->
    {FResult, FContext} =
        case Fun(8, Context) of
            {{ok, <<Value:64/integer-signed>>}, NContext} ->
                {{ok, Value}, NContext};
            {Result, NContext} ->
                {Result, NContext}
        end,
    {FResult, State#io_funs{context = FContext}}.

%%----------------------------------------------------------------------------
%% encode_hyper_uint
%%----------------------------------------------------------------------------

encode_hyper_uint(Value, _) when is_integer(Value) ->
    % Default is big.
    <<Value:64/integer-unsigned>>.

encode_hyper_uint(Value, _, State = #io_funs{context = Context, 
                                             write_fun = Fun}) 
        when is_integer(Value) ->
    % Default is big, and uses twos complement
    {Status, NContext} = Fun(8, <<Value:64/integer-unsigned>>, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_hyper_uint
%%----------------------------------------------------------------------------

decode_hyper_uint(<<Value:64/integer-unsigned, R/bitstring>>, _) ->
    {Value, R};
decode_hyper_uint(_, State = #io_funs{context = Context,
                                      read_fun = Fun}) ->
    {FResult, FContext} =
        case Fun(8, Context) of
            {{ok, <<Value:64/integer-unsigned>>}, NContext} ->
                {{ok, Value}, NContext};
            {Result, NContext} ->
                {Result, NContext}
        end,
    {FResult, State#io_funs{context = FContext}}.

%%----------------------------------------------------------------------------
%% encode_float
%%----------------------------------------------------------------------------

encode_float(Value, _) when is_float(Value) ->
    <<Value:32/float>>.

encode_float(Value, _, State = #io_funs{context = Context, 
                                        write_fun = Fun}) 
        when is_float(Value) ->
    % Default is big, and uses twos complement
    {Status, NContext} = Fun(4, <<Value:32/float>>, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_float
%%----------------------------------------------------------------------------

decode_float(<<Value:32/float, R/bitstring>>, _) ->
    {Value, R};
decode_float(_, State = #io_funs{context = Context,
                                 read_fun = Fun}) ->
    {FResult, FContext} =
        case Fun(4, Context) of
            {{ok, <<Value:32/float>>}, NContext} ->
                {{ok, Value}, NContext};
            {Result, NContext} ->
                {Result, NContext}
        end,
    {FResult, State#io_funs{context = FContext}}.

%%----------------------------------------------------------------------------
%% encode_double
%%----------------------------------------------------------------------------

encode_double(Value, _) when is_float(Value) ->
    <<Value:64/float>>.

encode_double(Value, _, State = #io_funs{context = Context, 
                                         write_fun = Fun}) 
        when is_float(Value) ->
    % Default is big, and uses twos complement
    {Status, NContext} = Fun(8, <<Value:64/float>>, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_double
%%----------------------------------------------------------------------------

decode_double(<<Value:64/float, R/bitstring>>, _) ->
    {Value, R};
decode_double(_, State = #io_funs{context = Context,
                                  read_fun = Fun}) ->
    {FResult, FContext} =
        case Fun(8, Context) of
            {{ok, <<Value:64/float>>}, NContext} ->
                {{ok, Value}, NContext};
            {Result, NContext} ->
                {Result, NContext}
        end,
    {FResult, State#io_funs{context = FContext}}.

%%----------------------------------------------------------------------------
%% encode_quad
%%----------------------------------------------------------------------------

encode_quad(Value, _) when is_float(Value) ->
    <<S:1,BE:11,NMB:52/bitstring>> = <<Value:64/float>>,
    NBE128 = BE - 1023 + 16383,
    NMB128 = <<NMB:52/bitstring,0:(112 - 52)>>,
    <<S:1,NBE128:15,NMB128:112/bitstring>>.

encode_quad(Value, CallArgs, State = #io_funs{context = Context, 
                                              write_fun = Fun}) 
        when is_float(Value) ->
    ToWrite = encode_quad(Value, CallArgs),
    {Status, NContext} = Fun(byte_size(ToWrite), ToWrite, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_quad
%%----------------------------------------------------------------------------

% This is not really decoding a 128 bit float as it turns it into a 64 bit 
%    float. I cannot get the :128/float qualifier to work in bit strings.
decode_quad(<<S:1,BE128:15,MB128:112/bitstring, R/bitstring>>, _) ->
    NBE64 = BE128 - 16383 + 1023,
    <<NM64:52/bitstring,_:(112 - 52)>> = MB128,
    <<Res:64/float>> = <<S:1,NBE64:11,NM64:52/bitstring>>,
    {Res, R};
decode_quad(CallArgs, State = #io_funs{context = Context,
                                       read_fun = Fun}) ->
    NumBits = 1 + 15 + 112,
    NumBytes = NumBits bsr 3,
    {FResult, FContext} =
        case Fun(NumBytes, Context) of
            {{ok, Raw}, NContext} ->
                case decode_quad(Raw, CallArgs) of
                    {Value, <<>>} ->
                        {{ok, Value}, NContext};
                    BD = _ ->
                        Msg = ?LogItMessage(decode_quad,
                                            "Bad decoded value returned: ~p.",
                                            [BD]),
                        {{error, Msg}, NContext}
                end;
            {Result, NContext} ->
                {Result, NContext}
        end,
    {FResult, State#io_funs{context = FContext}}.

%%----------------------------------------------------------------------------
%% encode_fixed_opaque
%%----------------------------------------------------------------------------

encode_fixed_opaque(Data, CallArgs = #call_args{}) when 
        is_list(Data) ->
    encode_fixed_opaque(list_to_binary(Data), CallArgs);
encode_fixed_opaque(Data, #call_args{len = Len}) when 
        is_integer(Len),
        is_binary(Data) ->
    NumBits = bit_size(Data),
    DesiredBits = (Len bsl 3),
    TotalBits =
        % 4 byte, 32 bit boundary
        case DesiredBits rem 32 of
            0 -> DesiredBits;
            LeftOver -> DesiredBits + 32 - LeftOver
        end,
    if
        NumBits =< TotalBits ->
            <<Data:NumBits/bitstring,0:(TotalBits - NumBits)>>;
        true ->
            % Don't know why I have to do this. Compiler complained.
            %     Above should not compile either then.
            LeftOverBits = NumBits - DesiredBits,
            <<NData:DesiredBits/bitstring, _:LeftOverBits>> = Data,
            PadBits = TotalBits - DesiredBits,
            <<NData:DesiredBits/bitstring,0:PadBits>>
    end.

encode_fixed_opaque(Data, CallArgs, State = #io_funs{context = Context, 
                                                     write_fun = Fun}) 
        when is_list(Data) ->
    ToWrite = encode_fixed_opaque(Data, CallArgs),
    {Status, NContext} = Fun(byte_size(ToWrite), ToWrite, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_fixed_opaque
%%----------------------------------------------------------------------------

decode_fixed_opaque(Data, #call_args{len = Len}) when 
        is_bitstring(Data) ->
    BytePadding = 
        case Len rem 4 of
            0 -> 0;
            LeftOver -> 4 - LeftOver
        end,
    BitPadding = BytePadding bsl 3,
    {R, Result} =
        pur_utls_misc:iterate(
            Len,
            {Data, []},
            fun 
                % Don't know why I had to add this first clause
                (_Count, {<<>>, Acc}) ->
                    {false, {<<>>, Acc}};
                (_Count, {NBitstring, Acc}) ->
                    <<N,NR/bitstring>> = NBitstring,
                    {true, {NR, [N|Acc]}}
            end),
    <<_:BitPadding, Res/bitstring>> = R,
    {lists:reverse(Result), Res};
decode_fixed_opaque(CallArgs = #call_args{len = Len}, 
                    State = #io_funs{context = Context,
                                     read_fun = Fun}) ->
    % Redundant with implementation of inner decode_fixed_opaque(...) call
    NumToRead = 
        case Len rem 4 of
            0 -> Len;
            LeftOver -> Len + (4 - LeftOver)
        end,
    {FResult, FContext} =
        case Fun(NumToRead, Context) of
            {{ok, Raw}, NContext} ->
                % Do NOT modify CallArgs with new length (NumToRead);
                %     otherwise extra data can be returned.
                case decode_fixed_opaque(Raw, CallArgs) of
                    {Value, <<>>} ->
                        {{ok, Value}, NContext};
                    BD = _ ->
                        Msg = ?LogItMessage(decode_fixed_opaque,
                                            "Bad decoded value returned: ~p.",
                                            [BD]),
                        {{error, Msg}, NContext}
                end;
            {Result, NContext} ->
                {Result, NContext}
        end,
    {FResult, State#io_funs{context = FContext}}.

%%----------------------------------------------------------------------------
%% encode_variable_opaque
%%----------------------------------------------------------------------------

encode_variable_opaque(Data, CallArgs = #call_args{len = Len}) when 
        is_integer(Len),
        is_list(Data) ->
    DLen = length(Data),
    NLen =
        if
            Len =< DLen -> Len;
            true -> DLen
        end,
    encode_variable_opaque(list_to_binary(Data), 
                           CallArgs#call_args{len = NLen});
% This version provides no dependency between embedded Len and 
%     passed in data. Can lead to errors.
encode_variable_opaque(Data, CallArgs = #call_args{len = Len}) when 
        is_integer(Len),
        is_binary(Data) ->
    MaxLen = (2 bsl 31) - 1,
    NLen =
        case Len < MaxLen of
            true -> Len;
            _ -> MaxLen
        end,
    <<(encode_uint(NLen, CallArgs)):32/bitstring,
      (encode_fixed_opaque(Data, CallArgs))/bitstring>>.

encode_variable_opaque(Data, 
                       CallArgs, 
                       State = #io_funs{context = Context, 
                                        write_fun = Fun}) ->
    ToWrite = encode_variable_opaque(Data, CallArgs),
    {Status, NContext} = Fun(byte_size(ToWrite), ToWrite, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_variable_opaque
%%----------------------------------------------------------------------------

decode_variable_opaque(<<Len:32/integer,Data/bitstring>>, _) ->
    decode_fixed_opaque(Data, #call_args{len = Len});
decode_variable_opaque(CallArgs, State = #io_funs{}) ->
    case decode_uint(CallArgs, State) of
        {{ok, Len}, NState} ->
            case decode_fixed_opaque(CallArgs#call_args{len = Len}, NState) of
                R = {{ok, _Value}, _NState} ->
                    R;
                {BD, NState} ->
                    Msg = ?LogItMessage(decode_variable_opaque,
                                        "Bad decoded value returned: ~p.",
                                        [BD]),
                    {{error, Msg}, NState}
            end;
        R = {_Result, _NState} ->
            R
    end.

%%----------------------------------------------------------------------------
%% encode_string
%%----------------------------------------------------------------------------

encode_string(String, CallArgs = #call_args{len = undefined}) when
        is_list(String) ->
    encode_variable_opaque(String, CallArgs#call_args{len = length(String)});
encode_string(String, CallArgs = #call_args{len = undefined}) when
        is_binary(String) ->
    encode_variable_opaque(String, 
                           CallArgs#call_args{len = byte_size(String)});
encode_string(String, CallArgs = #call_args{}) ->
    encode_variable_opaque(String, CallArgs).

encode_string(String, CallArgs, State = #io_funs{context = Context, 
                                                 write_fun = Fun}) ->
    ToWrite = encode_string(String, CallArgs),
    {Status, NContext} = Fun(byte_size(ToWrite), ToWrite, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_string
%%----------------------------------------------------------------------------

decode_string(Data, CallArgs = #call_args{}) ->
    decode_variable_opaque(Data, CallArgs);
decode_string(CallArgs, State = #io_funs{}) ->
    decode_variable_opaque(CallArgs, State).

%%----------------------------------------------------------------------------
%% encode_fixed_array
%%----------------------------------------------------------------------------

encode_fixed_array(Data,
                   #call_args{len = Len,
                              etype = EType,
                              call_args = ICallArgs,
                              codec_env = CodecEnv}) when
        is_list(Data),
        is_atom(EType)  ->
    % RealLen =
    %     % 4 byte, 32 bit boundary
    %     case Len rem 4 of
    %         0 -> Len;
    %         LeftOver -> Len + LeftOver
    %     end,
    case find_encoder(EType, CodecEnv) of
        undefined ->
            ?ThrowFlat(
                ?LogItMessage(
                    encode_fixed_array,
                    "EType: ~p not supported.",
                    [EType]));
        Fun ->
            {_, _, Results} =
                try
                    lists:foldl(
                        fun 
                            (_DataElem, {NLen, NCallArgs, Acc}) when 
                                    Len == NLen ->
                                % Obviously does not stop fold
                                {Len, NCallArgs, Acc};
                            (DataElem, {Count, [], Acc}) ->
                                FCallArgs = #call_args{codec_env = CodecEnv},
                                {Count + 1, 
                                 [], [Fun(DataElem, FCallArgs)|Acc]};
                            (DataElem, {Count, [NCallArgs|RCallArgs], Acc}) ->
                                FCallArgs = 
                                    NCallArgs#call_args{codec_env = CodecEnv},
                                {Count + 1, 
                                 RCallArgs, [Fun(DataElem, FCallArgs)|Acc]}
                        end,
                        {0, ICallArgs, []},
                        Data)
                catch Class:Error ->
                    ?LogItWithTrace(
                        encode_fixed_array,
                        "Error: ~p of class: ~p, with Len: ~p; rethrowing.",
                        [Error, Class, Len]),
                    throw({Class, Error})
                end,
            NResults = lists:reverse(Results),
            % GDEBUG
            % ?DebugIt(encode_fixed_array, "Results = ~p.~n", [NResults]),
            EncResult = << <<E/bitstring>> || E <- NResults >>,
            % GDEBUG
            % ?DebugIt(encode_fixed_array, "EncResult = ~p.~n", [EncResult]),
            Padding =  
                case bit_size(EncResult) rem 32 of 
                    0 -> 0;
                    L -> 32 - L
                end,
            <<EncResult/bitstring,0:Padding>>
    end.

encode_fixed_array(Data, CallArgs, State = #io_funs{context = Context, 
                                                    write_fun = Fun}) 
        when is_list(Data) ->
    ToWrite = encode_fixed_array(Data, CallArgs),
    {Status, NContext} = Fun(byte_size(ToWrite), ToWrite, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_fixed_array
%%----------------------------------------------------------------------------

decode_fixed_array(Data,
                   #call_args{
                      len = Len,
                      etype = EType,
                      call_args = DataCallArgs,
                      codec_env = CodecEnv = #etype_codecs{}}) when 
        is_bitstring(Data),
        is_atom(EType)  ->
    % Using first decoder found for EType
    case find_decoder(EType, CodecEnv) of
        undefined ->
            ?ThrowFlat(
                ?LogItMessage(
                    decode_fixed_array,
                    "EType: ~p not supported.",
                    [EType]));
        Fun ->
            {FinalData, _, Results} =
                try
                    pur_utls_misc:iterate(
                        Len, 
                        {Data, DataCallArgs, []}, 
                        fun 
                            (_Count, 
                             {<<>>, [], Acc}) ->
                                {false, {<<>>, [], Acc}};
                            (_Count, 
                             {NData, [], Acc}) ->
                                {Next, RestData} =
                                    Fun(NData, 
                                        #call_args{codec_env = CodecEnv}),
                                {true, {RestData, [], [Next|Acc]}};
                            (_Count, 
                             {NData, [NDCArgs|RCallArgs], Acc}) ->
                                {Next, RestData} =
                                    Fun(NData, 
                                        NDCArgs#call_args{
                                            codec_env = CodecEnv}),
                                {true, {RestData, RCallArgs, [Next|Acc]}}
                        end)
                catch Class:Error ->
                    ?LogItWithTrace(
                        decode_fixed_array,
                        "Error: ~p of class: ~p, with Len: ~p; rethrowing.",
                        [Error, Class, Len]),
                    throw({Class, Error})
                end,
            {lists:reverse(Results), FinalData}
    end;
decode_fixed_array(#call_args{
                      len = Len,
                      etype = EType,
                      call_args = DataCallArgs,
                      codec_env = CodecEnv = #etype_codecs{}},
                   State = #io_funs{}) when is_atom(EType)  ->
    % Using first decoder found for EType
    case find_io_decoder(EType, CodecEnv) of
        undefined ->
            ?ThrowFlat(
                ?LogItMessage(
                    decode_fixed_array,
                    "EType: ~p not supported.",
                    [EType]));
        Fun ->
            {_, Results, FState} =
                try
                    pur_utls_misc:iterate(
                        Len, 
                        {DataCallArgs, [], State}, 
                        fun 
                            (_Count, 
                             {[], Acc, NState}) ->
                                % GDEBUG
                                %?LogIt(decode_fixed_array,
                                %       "Acc: ~n~p.",
                                %       [Acc]),
                                case Fun(#call_args{codec_env = CodecEnv}, 
                                         NState) of
                                    {{ok, NextResult}, NNState} ->
                                        {true, 
                                         {[], [NextResult|Acc], NNState}};
                                    {R, NNState} ->
                                        {false, {[], [R|Acc], NNState}}
                                end;
                            (_Count, 
                             {[NCallArgs|RCallArgs], Acc, NState}) ->
                                case Fun(NCallArgs, NState) of
                                    {{ok, NextResult}, NNState} ->
                                        {true, 
                                         {RCallArgs, 
                                          [NextResult|Acc], NNState}};
                                    {R, NNState} ->
                                        {false, {RCallArgs, [R|Acc], NNState}}
                                end
                        end)
                catch Class:Error ->
                    ?LogItWithTrace(
                        decode_fixed_array,
                        "Error: ~p of class: ~p, with Len: ~p; rethrowing.",
                        [Error, Class, Len]),
                    throw({Class, Error})
                end,
            {{ok, lists:reverse(Results)}, FState}
    end.
 
%%----------------------------------------------------------------------------
%% encode_variable_array
%%----------------------------------------------------------------------------

encode_variable_array(Data,
                      CallArgs = #call_args{len = Len}) when 
        is_integer(Len),
        is_list(Data) ->
    DLen = length(Data),
    BLen =
        if
            Len =< DLen -> Len;
            true -> DLen
        end,
    MaxLen = (2 bsl 31) - 1,
    NLen =
        case BLen < MaxLen of
            true -> BLen;
            _ -> MaxLen
        end,
    <<(encode_uint(NLen, CallArgs)):32/bitstring,
      (encode_fixed_array(Data, CallArgs))/bitstring>>;
%% This version provides no dependency between embedded Len and 
%%     passed in data. Can lead to errors.
encode_variable_array(Data,
                      CallArgs = #call_args{len = Len,
                                            etype = EType,
                                            call_args = DataArgs}) when 
        is_integer(Len),
        is_list(DataArgs),
        is_atom(EType) ->
    % Error will occur if Len is "larger" than what Data holds
    MaxLen = (2 bsl 31) - 1,
    NLen =
        case Len < MaxLen of
            true -> Len;
            _ -> MaxLen
        end,
    <<(encode_uint(NLen, CallArgs)):32/bitstring,
      (encode_fixed_array(Data, CallArgs))/bitstring>>.

encode_variable_array(Data, CallArgs, State = #io_funs{context = Context, 
                                                       write_fun = Fun}) 
        when is_list(Data) ->
    ToWrite = encode_variable_array(Data, CallArgs),
    {Status, NContext} = Fun(byte_size(ToWrite), ToWrite, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_variable_array
%%----------------------------------------------------------------------------

decode_variable_array(<<Len:32/integer, Rest/bitstring>>,
                      CallArgs = #call_args{}) ->
    decode_fixed_array(Rest, CallArgs#call_args{len = Len});
decode_variable_array(CallArgs, State = #io_funs{}) ->
    case decode_uint(CallArgs, State) of
        {{ok, Len}, NState} ->
            case decode_fixed_array(CallArgs#call_args{len = Len}, NState) of
                R = {{ok, _Value}, _NState} ->
                    R;
                {BD, NState} ->
                    Msg = ?LogItMessage(decode_variable_array,
                                        "Bad decoded value returned: ~p.",
                                        [BD]),
                    {{error, Msg}, NState}
            end;
        R = {_Result, _NState} ->
            R
    end.

%%----------------------------------------------------------------------------
%% encode_struct
%%----------------------------------------------------------------------------

encode_struct(Data, #call_args{call_args = CallArgs,
                               codec_env = CodecEnv}) when
        is_list(Data),
        is_list(CallArgs) ->
        {_, Results} =
            lists:foldl(
                fun 
                    (_DataElem, {[], _Acc}) ->
                        ?ThrowFlat(
                            ?LogItMessage(
                                encode_struct,
                                "Empty inner args list.",
                                []));
                    (DataElem, {[NCallArgs|RCallArgs], Acc}) ->
                        DeclaredType = NCallArgs#call_args.etype,
                        {EType, FCallArgs} = 
                            case DeclaredType of
                                {OuterType, InnerType} ->
                                    {OuterType, 
                                     NCallArgs#call_args{
                                         etype = InnerType,
                                         codec_env = CodecEnv}};
                                _ -> 
                                    {DeclaredType, 
                                     NCallArgs#call_args{
                                         codec_env = CodecEnv}}
                            end,
                        case find_encoder(EType, CodecEnv) of
                            undefined -> 
                                ?ThrowFlat(
                                    ?LogItMessage(
                                        encode_struct,
                                        "Unknown encoder for type: ~p.",
                                        [EType]));
                            Fun ->
                                {RCallArgs, [Fun(DataElem, FCallArgs)|Acc]}
                        end
                end,
                {CallArgs, []},
                Data),
    << <<Next/bitstring>> || Next <- lists:reverse(Results) >>.

encode_struct(Data, 
              CallArgs,
              State = #io_funs{context = Context, 
                               write_fun = Fun}) when
        is_list(Data) ->
    ToWrite = encode_struct(Data, CallArgs),
    {Status, NContext} = Fun(byte_size(ToWrite), ToWrite, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_struct
%%----------------------------------------------------------------------------

decode_struct(Data, #call_args{call_args = CallArgs,
                               codec_env = CodecEnv = #etype_codecs{}}) when 
        is_bitstring(Data),
        is_list(CallArgs) ->
    {FData, _, Results} =
        pur_utls_misc:iterate(
            {Data, CallArgs, []},
            fun 
                ({<<>>, NCallArgs, Acc}) ->
                    {false, {<<>>, NCallArgs, Acc}};
                ({NData, [], Acc}) ->
                    {false, {NData, [], Acc}};
                ({NData, [NCallArgs|RCallArgs], Acc}) ->
                    DeclaredType = NCallArgs#call_args.etype,
                    {EType, FCallArgs} = 
                        case DeclaredType of
                            {OuterType, InnerType} ->
                                {OuterType, 
                                 NCallArgs#call_args{etype = InnerType}};
                            _ -> 
                                {DeclaredType, NCallArgs}
                        end,
                    case find_decoder(EType, CodecEnv) of
                        undefined ->
                            ?ThrowFlat(
                                ?LogItMessage(
                                    decode_struct,
                                    "Unknown decoder for type: ~p.",
                                    [EType]));
                        Fun ->
                            {Next, RData} = 
                                Fun(NData, 
                                    FCallArgs#call_args{codec_env = CodecEnv}),
                            {true, {RData, RCallArgs, [Next|Acc]}}
                    end
            end),
    {lists:reverse(Results), FData};
decode_struct(#call_args{call_args = CallArgs, 
                         codec_env = CodecEnv = #etype_codecs{}},
              State = #io_funs{}) when
        is_list(CallArgs) ->
    {_, Results, FState} =
        pur_utls_misc:iterate(
            {CallArgs, [], State},
            fun 
                (R = {[], _Acc, _NState}) ->
                    {false, R};
                ({[NCallArgs|RCallArgs], Acc, NState}) ->
                    DeclaredType = NCallArgs#call_args.etype,
                    {EType, FCallArgs} = 
                        case DeclaredType of
                            {OuterType, InnerType} ->
                                {OuterType, 
                                 NCallArgs#call_args{etype = InnerType}};
                            _ -> 
                                {DeclaredType, NCallArgs}
                        end,
                    case find_io_decoder(EType, CodecEnv) of
                        undefined ->
                            ?ThrowFlat(
                                ?LogItMessage(
                                    decode_struct,
                                    "Unknown decoder for type: ~p.",
                                    [EType]));
                        Fun ->
                            FunResult =
                                Fun(FCallArgs#call_args{codec_env = CodecEnv},
                                    NState),
                            case FunResult of
                                {{ok, Next}, FunState} ->
                                    {true, {RCallArgs, [Next|Acc], FunState}};
                                {BadR, FunState} ->
                                    {false, {RCallArgs, [BadR|Acc], FunState}}
                            end
                    end
            end),
    {{ok, lists:reverse(Results)}, FState}.

%%----------------------------------------------------------------------------
%% encode_union
%%----------------------------------------------------------------------------

encode_union({Discriminant, ArmValue},
             #call_args{env = Env, 
                        codec_env = CodecEnv = #etype_codecs{}}) ->
    case maps:get(Discriminant, Env, undefined) of
        undefined ->
            ?ThrowFlat(
                ?LogItMessage(
                    encode_union,
                    "Discriminant: ~p not a member of union:~n~p.",
                    [Discriminant, Env]));
        ArmCallArgs ->
            DeclaredType = ArmCallArgs#call_args.etype,
            {ArmType, FArmCallArgs} =
                case DeclaredType of
                    {OuterType, InnerType} ->
                        {OuterType, 
                         ArmCallArgs#call_args{etype = InnerType,
                                               codec_env = CodecEnv}};
                    _ ->
                        {DeclaredType, 
                         ArmCallArgs#call_args{codec_env = CodecEnv}}
                end,
            case find_encoder(ArmType, CodecEnv) of
                undefined -> 
                    ?ThrowFlat(
                        ?LogItMessage(
                            encode_union,
                            "ArmType: ~p , for Discriminant: ~p, "
                                "not supported.",
                            [ArmType, Discriminant]));
                Fun ->
                    <<(encode_uint(Discriminant, #call_args{}))/bitstring,
                       (Fun(ArmValue, FArmCallArgs))/bitstring>>
            end
   end.

encode_union(Data = {_Discriminant, _ArmValue}, 
             CallArgs, 
             State = #io_funs{context = Context, 
                              write_fun = Fun}) ->
    ToWrite = encode_union(Data, CallArgs),
    {Status, NContext} = Fun(byte_size(ToWrite), ToWrite, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_union
%%----------------------------------------------------------------------------

decode_union(<<Discriminant:32/integer-unsigned, ArmData/bitstring>>,
             #call_args{env = Env,
                        codec_env = CodecEnv = #etype_codecs{}}) ->
    case maps:get(Discriminant, Env, undefined) of
        undefined -> 
            ?ThrowFlat(
                ?LogItMessage(
                    decode_union,
                    "Discriminant: ~p not found in call args env.",
                    [Discriminant]));
        ArmCallArgs ->
            DeclaredType = ArmCallArgs#call_args.etype,
            {ArmType, FArmCallArgs} =
                case DeclaredType of
                    {OuterType, InnerType} ->
                        {OuterType, ArmCallArgs#call_args{etype = InnerType}};
                    _ ->
                        {DeclaredType, ArmCallArgs}
                end,
            case find_decoder(ArmType, CodecEnv) of
                undefined ->
                    ?ThrowFlat(
                        ?LogItMessage(
                            decode_union,
                            "ArmType: ~p not supported.",
                            [ArmType]));
                Fun ->
                    Fun(ArmData, FArmCallArgs#call_args{codec_env = CodecEnv})
            end
    end;
decode_union(CallArgs = #call_args{env = Env,
                                   codec_env = CodecEnv = #etype_codecs{}},
             State = #io_funs{}) ->
    {FResult, FState} =
        case decode_uint(CallArgs, State) of
            {{ok, Discriminant}, NState} ->
                case maps:get(Discriminant, Env, undefined) of
                    undefined -> 
                        ?ThrowFlat(
                            ?LogItMessage(
                                decode_union,
                                "Discriminant: ~p not found in call args env.",
                                [Discriminant]));
                    ArmCallArgs ->
                        DeclaredType = ArmCallArgs#call_args.etype,
                        {ArmType, FArmCallArgs} =
                            case DeclaredType of
                                {OuterType, InnerType} ->
                                    {OuterType, 
                                     ArmCallArgs#call_args{etype = InnerType}};
                                _ ->
                                    {DeclaredType, ArmCallArgs}
                            end,
                        case find_io_decoder(ArmType, CodecEnv) of
                            undefined ->
                                ?ThrowFlat(
                                    ?LogItMessage(
                                        decode_union,
                                        "ArmType: ~p not supported.",
                                        [ArmType]));
                            Fun ->
                                Fun(FArmCallArgs#call_args{
                                        codec_env = CodecEnv}, 
                                    NState)
                        end
                end;
            R = {_Result, _NState} ->
                R
        end,
    {FResult, FState}.

%%----------------------------------------------------------------------------
%% encode_void
%%----------------------------------------------------------------------------

encode_void() ->
    encode_void(undefined, #call_args{}).

encode_void(_, #call_args{}) ->
    <<>>.

encode_void(_, _CallArgs, State = #io_funs{}) ->
    {ok, State}.

%%----------------------------------------------------------------------------
%% decode_void
%%----------------------------------------------------------------------------

decode_void(Data, #call_args{}) ->
    {[], Data};
decode_void(_CallArgs, State = #io_funs{}) ->
    {{ok, []}, State}.

%%----------------------------------------------------------------------------
%% encode_optional
%%----------------------------------------------------------------------------

encode_optional({true, ArmValue}, 
                CallArgs = #call_args{etype = ArmType, 
                                      codec_env = 
                                          CodecEnv = #etype_codecs{}}) ->
    case find_encoder(ArmType, CodecEnv) of
        undefined ->
            ?ThrowFlat(
                ?LogItMessage(
                    {encode_optional, true},
                    "ArmType: ~p not supported.",
                    [ArmType]));
        Fun ->
            <<(encode_uint(1, CallArgs))/bitstring,
              (Fun(ArmValue, CallArgs))/bitstring>>
   end;
encode_optional({false, _}, CallArgs) ->
   <<(encode_uint(0, CallArgs))/bitstring, 
     (encode_void())/bitstring>>.

encode_optional(Data = {Flag, _ArmValue}, 
                CallArgs, 
                State = #io_funs{context = Context,
                                 write_fun = Fun}) when 
            Flag == true; Flag == false ->
    ToWrite = encode_optional(Data, CallArgs),
    {Status, NContext} = Fun(byte_size(ToWrite), ToWrite, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_optional
%%----------------------------------------------------------------------------

decode_optional(<<1:32/integer, Data/bitstring>>, 
                CallArgs = 
                    #call_args{
                        etype = ArmType, 
                        codec_env = CodecEnv = #etype_codecs{}}) when 
        is_atom(ArmType) ->
    case find_decoder(ArmType, CodecEnv) of
        undefined ->
            ?ThrowFlat(
                ?LogItMessage(
                    {decode_optional, true},
                    "Unknown decoder for arm type: ~p, ",
                    [ArmType]));
        Fun ->
            Fun(Data, CallArgs)
    end;
decode_optional(<<0:32/integer, Data/bitstring>>, _CallArgs) ->
    {[], Data};
decode_optional(CallArgs  = #call_args{
                                etype = ArmType, 
                                codec_env = CodecEnv = #etype_codecs{}},
                State = #io_funs{}) when 
        is_atom(ArmType) ->
    {FResult, FState} =
        case decode_int(CallArgs, State) of
            {{ok, 0}, NState} ->
                {{ok, []}, NState};
            {{ok, 1}, NState} ->
                case find_io_decoder(ArmType, CodecEnv) of
                    undefined ->
                        ?ThrowFlat(
                            ?LogItMessage(
                                {decode_optional, true},
                                "Unknown decoder for arm type: ~p, ",
                                [ArmType]));
                    Fun ->
                        Fun(CallArgs, NState)
                end;
            R = {_Result, _NState} ->
                R
        end,
    {FResult, FState}.

%%----------------------------------------------------------------------------
%% encode_generic
%%----------------------------------------------------------------------------

encode_generic(Data, 
               CallArgs = 
                   #call_args{etype = DeclaredType,
                              codec_env = CodecEnv = #etype_codecs{}}) ->
    {EType, NCallArgs} = 
        case DeclaredType of
            {OuterType, InnerType} ->
                {OuterType, CallArgs#call_args{etype = InnerType}};
            _ -> 
                {DeclaredType, CallArgs}
        end,
    case find_encoder(EType, CodecEnv) of
        undefined -> 
            ?ThrowFlat(
                ?LogItMessage(
                    encode_generic,
                    "Unknown encoder for type: ~p.",
                    [EType]));
        Fun ->
            Fun(Data, NCallArgs)
    end.

encode_generic(Data, 
               CallArgs,
               State = #io_funs{context = Context,
                                write_fun = Fun}) ->
    ToWrite = encode_generic(Data, CallArgs),
    {Status, NContext} = Fun(byte_size(ToWrite), ToWrite, Context),
    {Status, State#io_funs{context = NContext}}.

%%----------------------------------------------------------------------------
%% decode_generic
%%----------------------------------------------------------------------------

decode_generic(Data, 
               CallArgs = 
                   #call_args{etype = DeclaredType,
                              codec_env = CodecEnv = #etype_codecs{}}) when 
        is_bitstring(Data) ->
    {EType, NCallArgs} = 
        case DeclaredType of
            {OuterType, InnerType} ->
                {OuterType, CallArgs#call_args{etype = InnerType}};
            _ -> 
                {DeclaredType, CallArgs}
        end,
    case find_decoder(EType, CodecEnv) of
        undefined -> 
            ?ThrowFlat(
                ?LogItMessage(
                    encode_generic,
                    "Unknown encoder for type: ~p.",
                    [EType]));
        Fun ->
            Fun(Data, NCallArgs)
    end;
decode_generic(CallArgs = 
                   #call_args{etype = DeclaredType,
                              codec_env = CodecEnv = #etype_codecs{}},
               State = #io_funs{}) ->
    {EType, NCallArgs} = 
        case DeclaredType of
            {OuterType, InnerType} ->
                {OuterType, CallArgs#call_args{etype = InnerType}};
            _ -> 
                {DeclaredType, CallArgs}
        end,
    case find_io_decoder(EType, CodecEnv) of
        undefined -> 
            ?ThrowFlat(
                ?LogItMessage(
                    encode_generic,
                    "Unknown encoder for type: ~p.",
                    [EType]));
        Fun ->
            Fun(NCallArgs, State)
    end.

