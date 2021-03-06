%%% -*- coding: utf-8 -*-
%%%-------------------------------------------------------------------
%%% @author Laura M. Castro <lcastro@udc.es>
%%% @copyright (C) 2014
%%% @doc
%%%     Generate human-readable versions of test models =>
%%%     by presenting human-readable versions of representative test
%%%     cases that cover the model
%%% @end
%%%-------------------------------------------------------------------

-module(readspec).

-export([suite/2, counterexample/3]).

-include("readspec.hrl").

suite(Module, Property) ->
	suite(Module, Property, ?NUMTESTS).

suite(Module, Property, NumTests) ->
    ?DEBUG("Cover-compiling module: ~p~n", [Module]),
    FeatureFile = erlang:atom_to_list(Module) ++ ".feature",
    {ok, Module} = cover:compile(Module),
    Suite = eqc_suite:coverage_based([Module],
				     eqc:numtests(NumTests, erlang:apply(Module, Property, []))),
    ?DEBUG("Cucumberising set of test cases: ~p~n", [Suite]),
    ok = file:write_file(FeatureFile,
			 clean(erl_prettypr:format(cucumberise_suite(Module, Property, eqc_suite:cases(Suite)),
						   ?PRETTYPR_OPTIONS))).

counterexample(Module, Property, [Counterexample]) ->
    FeatureFile = erlang:atom_to_list(Property) ++ ".counterexample.feature",
    ?DEBUG("Generating counterexample file: ~p~n", [FeatureFile]),
    Scenario = cucumberise_teststeps_aux(Module, Property, Counterexample, []),
    ?DEBUG("Reversing scenario: ~p~n", [readspec_inspect:falsify(Scenario)]),
    ok = file:write_file(FeatureFile, clean(erl_prettypr:format(readspec_inspect:falsify(Scenario),
                                                                ?PRETTYPR_OPTIONS))).

%%% -------------------------------------------------------------- %%%

cucumberise_suite(Module, Property, Suite) ->
    ModuleStr = erlang:atom_to_list(Module),
    FeatureName = try string:substr(ModuleStr, 1, string:str(ModuleStr, "_eqc")-1) of X -> X catch _:_ -> ModuleStr end,
    Scenarios = cucumberise_testcases(Module, Property, Suite, []),
    erl_syntax:form_list([erl_syntax:string(?FEATURE ++ FeatureName),
			  erl_syntax:comment(?EMPTY),
			  erl_syntax:comment(2, [readspec_inspect:model_description(Module)])] ++
			     [ erl_syntax:form_list([erl_syntax:comment(?EMPTY),
						     erl_syntax:comment(?EMPTY),
						     erl_syntax:string(?SCENARIO ++
									   readspec_inspect:property_description(Module, Property)),
						     Scenario,
						     erl_syntax:comment(?EMPTY)]) || Scenario <- Scenarios, Scenario =/= [] ]).


cucumberise_testcases(_Module, _Property, [], CucumberisedTestCases) ->
    lists:reverse(CucumberisedTestCases);
cucumberise_testcases(Module, Property, [TestCase | MoreTestCases], CucumberisedTestCases) ->
    cucumberise_testcases(Module, Property, MoreTestCases, [cucumberise_teststeps(Module, Property, TestCase) | CucumberisedTestCases]).


cucumberise_teststeps(Module, Property, [TestCase]) ->
    cucumberise_teststeps_aux(Module, Property, TestCase, []);
cucumberise_teststeps(Module, Property, TestCase) ->
    cucumberise_teststeps_aux(Module, Property, TestCase, []).

cucumberise_teststeps_aux(_Module, _Property, [], []) ->
    [];
cucumberise_teststeps_aux(Module, Property, [], CucumberisedTestSteps) ->
    erl_syntax:form_list(cucumberise(Module, Property,
				     {scenario, lists:reverse(CucumberisedTestSteps)}));
% tests for QC properties
cucumberise_teststeps_aux(Module, Property, Value, []) when is_tuple(Value) ->
    erl_syntax:form_list(cucumberise(Module, Property,
				     {scenario, Value}));
cucumberise_teststeps_aux(Module, Property, Value, []) when is_integer(Value) ->
    erl_syntax:form_list(cucumberise(Module, Property,
				     {scenario, Value}));
cucumberise_teststeps_aux(Module, Property, Value, []) when is_atom(Value) ->
    erl_syntax:form_list(cucumberise(Module, Property,
				     {scenario, Value}));
cucumberise_teststeps_aux(Module, Property, Values, []) when is_list(Values) ->
    erl_syntax:form_list(cucumberise(Module, Property,
				     {scenario, Values}));
% === ==== ==== ====
% test steps for QC state machines
cucumberise_teststeps_aux(Module, Property, [{set,_,Call={call,_Module,_Function,_Args}} | MoreSteps], CucumberisedTestSteps) ->
    cucumberise_teststeps_aux(Module, Property, MoreSteps, [Call | CucumberisedTestSteps]).


% we remove spureous cases such as {scenario, []}
cucumberise(_Module, _Property, {scenario, []}) ->
    [];
% cucumberise QC property scenario
cucumberise(Module, Property, {scenario, Value}) when is_tuple(Value) ->
    explain(Module, Property, Value, []);
cucumberise(Module, Property, {scenario, Value}) when is_integer(Value) ->
    explain(Module, Property, Value, []);
cucumberise(Module, Property, {scenario, Value}) when is_atom(Value) ->
    explain(Module, Property, Value, []);
cucumberise(Module, Property, {scenario, Values}) when is_list(Values) ->
    explain(Module, Property, Values, []);
% === ==== ==== ====
% cucumberise QC state machine scenario
cucumberise(Module, Property, {scenario, [Call={call,_,_,_} | MoreSteps]}) ->
    explain(Module, Property, Call, MoreSteps).


explain(_Module, _Property, {call,_,Function,Args}, MoreSteps) ->
    ?GIVEN ++ enumerate_list([Args], length(Args)) ++
	?WHEN ++ io_lib:fwrite("~p", [Function]) ++
	explain_also(MoreSteps) ++
	?THEN  ++ "** insert property postcondition here ** ";
explain(Module, Property, Values, []) ->
    {PropertyDefinition, NValues, Aliases} = readspec_inspect:property_definition(Module, Property, Values),
    ?DEBUG("Property definition ~p with ~p values of aliases ~p~n", [PropertyDefinition, NValues, Aliases]),
    [erl_syntax:comment(?EMPTY),
     erl_syntax:string(?GIVEN),
     erl_syntax:form_list(enumerate_list(Values, NValues, Aliases)),
     erl_syntax:string(?THEN ++ PropertyDefinition),
     erl_syntax:comment(?EMPTY)].


explain_also([]) ->
    "";
explain_also([{call,_Module,Function,_ArgsNotUsedRightNow} | MoreSteps]) ->
    " " ++ ?AND ++ io_lib:fwrite("~p", [Function]) ++
	explain_also(MoreSteps).


% ----- ----- ----- ----- ----- -----  ----- ----- ----- ----- ----- %

enumerate_list(Integer, 1) when is_integer(Integer) ->
    identify(Integer);
enumerate_list(Atom, 1) when is_atom(Atom) ->
    identify(Atom);
enumerate_list(Tuple, N) when is_tuple(Tuple) ->
    enumerate_list(erlang:tuple_to_list(Tuple), N);
enumerate_list(List, 1) when is_list(List) ->
    identify(List);
enumerate_list(List, _N) when is_list(List) -> % TODO: sanity check is N = length(List)
    L = [ [erl_syntax:string(?AND) | identify(X)] || X <- List],
    [_H | T] = lists:flatten(L),
    T;
enumerate_list(Other, 0) ->
    enumerate_list(Other, 1).

enumerate_list(Values, NValues, []) ->
    enumerate_list(Values, NValues);
enumerate_list(Values, NValues, Aliases) ->
    enumerate_list(Values, NValues) ++ [ erl_syntax:string(?AND),
				         erl_syntax:string(?ALIAS) ] ++ 
	[ erl_syntax:string(erlang:atom_to_list(Alias) ++ ", ") || Alias <- Aliases ] ++
	[ erl_syntax:comment(?EMPTY) ].

identify(X) ->
    ASTofX = erl_syntax:abstract(X),
    [erl_syntax:string(?OPERAND),
     erl_syntax:string(type_of(X)), % === TODO: check consistency with property definition
     ASTofX,
     erl_syntax:comment(?EMPTY)].

type_of([]) ->
    ?LIST;
type_of(X) when is_integer(X) ->
    ?INTEGER;
type_of(X) when is_boolean(X) ->
    ?BOOLEAN;
type_of(X) when is_atom(X) ->
    ?ATOM;
type_of(X) when is_list(X) ->
    case is_string(X) of
	true  -> ?STRING;
	false -> ?LIST
    end;
type_of(X) when is_tuple(X) ->
    ?TUPLE;
type_of(_) ->
    ?UNKNOWN.

is_string(X) ->
    is_list(X) andalso lists:all(fun(C) -> is_char(C) end, X).

is_char(C) when is_integer(C) ->
    ((32 =< C) andalso (C =< 126)) orelse ((161 =< C) andalso (C =< 255));
is_char(_C) ->
    false.

clean(StringStream) ->
    trim_lines(lists:filter(fun($") -> false;
			       ($%) -> false;
			       (_C) -> true   end,
			    StringStream)).

trim_lines([]) ->
    [];
trim_lines([$\n, $\n, $\n, $\n | T]) ->
    [$\n, $\n | trim_lines(T)];
trim_lines([$\n, $\n, $n | T]) ->
    [$\n | trim_lines(T)];
trim_lines([$\n, $\n | T]) ->
    trim_lines(T);
trim_lines([$\t | T]) ->
    [32 | trim_lines(T)];
trim_lines([92, 110 | T]) -> % escaped newline
    trim_lines(T);
trim_lines([92, 116 | T]) -> % escaped tab
    trim_lines([32 | T]);
trim_lines([32, 32 | T]) -> % multiple whitespaces
    trim_lines([32 | T]);
trim_lines([$b,$e,$g,$i,$n | T]) ->
    trim_lines(T);
trim_lines([$e,$n,$d | T]) ->
    trim_lines(T);
trim_lines([H|T]) ->
    [H | trim_lines(T)].
