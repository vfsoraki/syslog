%%%=============================================================================
%%% Copyright 2016, Tobias Schlager <schlagert@github.com>
%%%
%%% Permission to use, copy, modify, and/or distribute this software for any
%%% purpose with or without fee is hereby granted, provided that the above
%%% copyright notice and this permission notice appear in all copies.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
%%%=============================================================================

-module(syslog_test).

-include_lib("eunit/include/eunit.hrl").

-include("syslog.hrl").

-define(TEST_PORT, 31337).
-define(TIMEOUT,   100).

%%%=============================================================================
%%% TESTS
%%%=============================================================================

rfc3164_test() ->
    {ok, Socket} = setup(rfc3164, debug),

    Pid = pid_to_list(self()),
    Month = "(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)",
    Date = Month ++ " (\\s|\\d)\\d \\d\\d:\\d\\d:\\d\\d",

    ?assertEqual(ok, syslog:info_msg("hello world")),
    Re1 = "<30>" ++ Date ++ " .+ \\w+\\[\\d+\\] " ++ Pid ++ " - hello world",
    ?assertMatch({match, _}, re:run(read(Socket), Re1)),

    ?assertEqual(ok, syslog:msg(critical, "hello world", [])),
    Re2 = "<26>" ++ Date ++ " .+ \\w+\\[\\d+\\] " ++ Pid ++ " - hello world",
    ?assertMatch({match, _}, re:run(read(Socket), Re2)),

    ?assertEqual(ok, syslog:error_msg("hello ~s", ["world"])),
    Re3 = "<27>" ++ Date ++ " .+ \\w+\\[\\d+\\] " ++ Pid ++ " - hello world",
    ?assertMatch({match, _}, re:run(read(Socket), Re3)),

    ?assertEqual(ok, error_logger:error_msg("hello ~s", ["world"])),
    ?assertMatch({match, _}, re:run(read(Socket), Re3)),

    ?assertEqual(ok, syslog:error_msg("~nhello~n~s~n", ["world"])),
    Re4 = "<27>" ++ Date ++ " .+ \\w+\\[\\d+\\] " ++ Pid ++ " - hello",
    ?assertMatch({match, _}, re:run(read(Socket), Re4)),
    Re5 = "<27>" ++ Date ++ " .+ \\w+\\[\\d+\\] " ++ Pid ++ " - world",
    ?assertMatch({match, _}, re:run(read(Socket), Re5)),

    ?assertEqual(ok, syslog:msg(crash, "hello world", [])),
    Re6 = "<131>" ++ Date ++ " .+ \\w+\\[\\d+\\] " ++ Pid ++ " - hello world",
    ?assertMatch({match, _}, re:run(read(Socket), Re6)),

    teardown(Socket).

rfc5424_test() ->
    {ok, Socket} = setup(rfc5424, debug),

    Pid = pid_to_list(self()),
    Date = "\\d\\d\\d\\d-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d\\.\\d\\d\\d\\d\\d\\d(Z|(\\+|-)\\d\\d:\\d\\d)",

    ?assertEqual(ok, syslog:info_msg("hello world")),
    Re1 = "<30>1 " ++ Date ++ " .+ \\w+ \\d+ " ++ Pid ++ " - hello world",
    ?assertMatch({match, _}, re:run(read(Socket), Re1)),

    ?assertEqual(ok, syslog:msg(critical, "hello world", [])),
    Re2 = "<26>1 " ++ Date ++ " .+ \\w+ \\d+ " ++ Pid ++ " - hello world",
    ?assertMatch({match, _}, re:run(read(Socket), Re2)),

    ?assertEqual(ok, syslog:error_msg("hello ~s", ["world"])),
    Re3 = "<27>1 " ++ Date ++ " .+ \\w+ \\d+ " ++ Pid ++ " - hello world",
    ?assertMatch({match, _}, re:run(read(Socket), Re3)),

    ?assertEqual(ok, error_logger:error_msg("hello ~s", ["world"])),
    ?assertMatch({match, _}, re:run(read(Socket), Re3)),

    ?assertEqual(ok, syslog:error_msg("~nhello~n~s~n", ["world"])),
    Re4 = "<27>1 " ++ Date ++ " .+ \\w+ \\d+ " ++ Pid ++ " - hello",
    ?assertMatch({match, _}, re:run(read(Socket), Re4)),
    Re5 = "<27>1 " ++ Date ++ " .+ \\w+ \\d+ " ++ Pid ++ " - world",
    ?assertMatch({match, _}, re:run(read(Socket), Re5)),

    ?assertEqual(ok, syslog:msg(crash, "hello world", [])),
    Re6 = "<131>1 " ++ Date ++ " .+ \\w+ \\d+ " ++ Pid ++ " - hello world",
    ?assertMatch({match, _}, re:run(read(Socket), Re6)),

    teardown(Socket).

log_level_test_() ->
    {timeout,
     5,
     fun() ->
             {ok, Socket} = setup(rfc5424, notice),

             Pid = pid_to_list(self()),
             Date = "\\d\\d\\d\\d-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d\\.\\d\\d\\d\\d\\d\\d(Z|(\\+|-)\\d\\d:\\d\\d)",

             ?assertEqual(ok, syslog:debug_msg("hello world")),
             ?assertEqual(ok, syslog:info_msg("hello world")),
             ?assertEqual(timeout, read(Socket)),

             ?assertEqual(ok, syslog:set_log_level(debug)),

             ?assertEqual(ok, syslog:debug_msg("hello world")),
             Re1 = "<31>1 " ++ Date ++ " .+ \\w+ \\d+ " ++ Pid ++ " - hello world",
             ?assertMatch({match, _}, re:run(read(Socket), Re1)),

             teardown(Socket)
     end}.

error_logger_test_() ->
    {timeout,
     5,
     fun() ->
             {ok, Socket} = setup(rfc3164, debug, 20),

             erlang:suspend_process(whereis(error_logger)),

             Send = fun(I) -> error_logger:info_msg("Message ~w", [I]) end,
             ok = lists:foreach(Send, lists:seq(1, 30)),

             erlang:resume_process(whereis(error_logger)),

             Receive = fun(_) -> ?assert(is_list(read(Socket))) end,
             ok = lists:foreach(Receive, lists:seq(1, 18)),
             ?assertEqual(timeout, read(Socket)),

             teardown(Socket)
     end}.

%%%=============================================================================
%%% internal functions
%%%=============================================================================

setup(Protocol, LogLevel) -> setup(Protocol, LogLevel, infinity).

setup(Protocol, LogLevel, Limit) ->
    ?assertEqual(ok, application:start(sasl)),
    AppFile = filename:join(["..", "src", "syslog.app.src"]),
    {ok, [AppSpec]} = file:consult(AppFile),
    ?assertEqual(ok, load(AppSpec)),
    ?assertEqual(ok, application:set_env(syslog, dest_port, ?TEST_PORT)),
    ?assertEqual(ok, application:set_env(syslog, protocol, Protocol)),
    ?assertEqual(ok, application:set_env(syslog, crash_facility, local0)),
    ?assertEqual(ok, application:set_env(syslog, log_level, LogLevel)),
    ?assertEqual(ok, application:set_env(syslog, msg_queue_limit, Limit)),
    ?assertEqual(ok, application:set_env(syslog, no_progress, true)),
    ?assertEqual(ok, application:start(syslog)),
    ?assertEqual(ok, empty_mailbox()),
    gen_udp:open(?TEST_PORT, [binary]).

teardown(Socket) ->
    application:stop(syslog),
    application:stop(sasl),
    application:unset_env(syslog, dest_port),
    application:unset_env(syslog, protocol),
    application:unset_env(syslog, crash_facility),
    application:unset_env(syslog, log_level),
    application:unset_env(syslog, msg_queue_limit),
    application:unset_env(syslog, drop_percentage),
    gen_udp:close(Socket).

load(App) -> load(App, application:load(App)).
load(_, ok) -> ok;
load(App, {error, {already_loaded, App}}) -> ok.

read(Socket) ->
    receive
        {udp, Socket, _, _, Bin} -> binary_to_list(Bin)
    after
        500 -> timeout
    end.

empty_mailbox() -> receive _ -> empty_mailbox() after ?TIMEOUT -> ok end.
