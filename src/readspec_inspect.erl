%%% -*- coding: utf-8 -*-
%%%-------------------------------------------------------------------
%%% @author Laura M. Castro <lcastro@udc.es>
%%% @copyright (C) 2014
%%% @doc
%%%     Utility module to inspect code of test properties and models.
%%% @end
%%%-------------------------------------------------------------------

-module(readspec_inspect).

-include("records.hrl").
-include_lib("xmerl/include/xmerl.hrl").

-export([model_description/1, property_description/2]).
-export([property_definition/3, property_definition/4]).

%% @doc Extracts the module description from the edoc comments on the source code
%% @end
-spec model_description(ModelModule :: atom()) -> ModuleDescription :: string().
model_description(ModelModule) ->
	extract_module_description(ModelModule).

%% @doc Extracts the property description from the edoc comments on the source code
%% @end
-spec property_description(ModelModule :: atom(),
						   PropertyName :: atom()) -> PropertyDescription :: string().
property_description(ModelModule, PropertyName) ->
	extract_function_description(ModelModule, PropertyName).

%% @doc Extracts the body of a property as a string from the source code
%% @end
-spec property_definition(ModelModule :: atom(),
						  PropertyName :: atom(),
						  Values :: tuple()) -> PropertyBody :: string().
property_definition(ModelModule, PropertyName, Values) ->
	property_definition(ModelModule, PropertyName, [], Values).

-spec property_definition(ModelModule :: atom(),
						  PropertyName :: atom(),
						  Args :: term(),
						  Values :: tuple()) -> PropertyBody :: string().
property_definition(ModelModule, PropertyName, Arguments, Values) ->
	FullModelModuleName = list_to_atom(atom_to_list(ModelModule) ++ ".erl"),
	ValuesAsAtoms = [to_atom(Value) || Value <- tuple_to_list(Values)],
	[Exp] = see:scan_func_str_args(FullModelModuleName, PropertyName, Arguments),
	extract_property_definition(Exp, ValuesAsAtoms).
	


%%% -------------------------------------------------------------- %%%

extract_module_description(ModelModule) ->
	XML = get_xml_version(ModelModule),
	module = XML#xmlElement.name,
	Descriptions = lists:flatten([ Element#xmlElement.content || Element <- XML#xmlElement.content,
																 Element#xmlElement.name == description ]),
	[FullDescription] = lists:flatten([ Element#xmlElement.content || Element <- Descriptions,
																	  Element#xmlElement.name == fullDescription ]),
	FullDescription#xmlText.value.


extract_function_description(ModelModule, Function) ->
	FunctionName = erlang:atom_to_list(Function),
	XML = get_xml_version(ModelModule),
	module = XML#xmlElement.name,
	Functions = lists:flatten([ Element#xmlElement.content || Element <- XML#xmlElement.content,
															  Element#xmlElement.name == functions ]),
	[FunctionDescription] = lists:filter(fun(Element) when is_record(Element, xmlElement) -> 
												 [] =/= [ Element#xmlElement.content || Attribute <- Element#xmlElement.attributes,
																						Attribute#xmlAttribute.name == name,
																						Attribute#xmlAttribute.value == FunctionName ]
										 end, Functions),
	function = FunctionDescription#xmlElement.name,
	Descriptions = lists:flatten([ Element#xmlElement.content || Element <- FunctionDescription#xmlElement.content,
																 Element#xmlElement.name == description ]),
	[FullDescription] = lists:flatten([ Element#xmlElement.content || Element <- Descriptions,
																	  Element#xmlElement.name == fullDescription ]),
	FullDescription#xmlText.value.

get_xml_version(Module) ->
	FileName = erlang:atom_to_list(Module) ++ ".erl",
	{Module, XML} = edoc_extract:source(FileName, edoc_lib:get_doc_env(FileName), []),
	XML.

% ----- ----- ----- ----- ----- -----  ----- ----- ----- ----- ----- %

extract_property_definition(Exp, Values) when is_record(Exp, exp_iface) ->
	[AppDef] = Exp#exp_iface.var_defs,
	extract_property_definition_aux(AppDef, Values).

extract_property_definition_aux(App, Values) when is_record(App, apply) ->
	[FunDef] = lists:flatten([ Clauses || {'fun',_,{clauses,Clauses}} <- App#apply.arg_list]),
	[FunBody] = erl_syntax:clause_body(FunDef),
	erl_prettypr:format(replace_values(FunBody, Values)).

replace_values(Exp, Values) ->
	{NewExp,_NotBindedValues,_BindedValues} = transverse_exp(Exp, Values, []),
	NewExp.

transverse_exp({var,N,Name}, [Value|MoreValues], UsedValues) when is_atom(Name) ->
	case lists:keyfind(Name, 1, UsedValues) of
		false ->
			{{var,N,Value}, MoreValues, [{Name,Value}|UsedValues]};
		{Name,UsedValue} ->
			{{var,N,UsedValue}, [Value|MoreValues], UsedValues}
	end;
transverse_exp(Exp, Values, UsedValues) when is_tuple(Exp) ->
	ExpList = tuple_to_list(Exp),
	{NewExpList, LessValues, MoreUsedValues} = transverse_exp(ExpList, Values, UsedValues),
	{list_to_tuple(NewExpList), LessValues, MoreUsedValues};
transverse_exp(Exp, Values, UsedValues) when is_list(Exp) ->
	lists:foldl(fun(Member, {RExp, Vs, UVs}) ->
						case transverse_exp(Member, Vs, UVs) of
							{{var,N,Value}, MoreValues, MoreUsedValues} ->
								{RExp++[{var,N,Value}], MoreValues, MoreUsedValues};
							{Other, MoreVs, MoreUsedVs} ->
								{RExp++[Other], MoreVs, MoreUsedVs}
						end
				end, {[], Values, UsedValues}, Exp);
transverse_exp(Exp, Values, UsedValues) ->
	{Exp, Values, UsedValues}.
	

to_atom(Term) when is_integer(Term) ->
	list_to_atom(integer_to_list(Term));
to_atom([]) ->
	'[]';
to_atom(Term) when is_list(Term) ->
	list_to_atom(Term).

%    {ok, Forms} = epp:parse_file(FileName, [], []),
%    Comments = erl_comment_scan:file(FileName),
%    AST = erl_recomment:recomment_forms(Forms, Comments),
