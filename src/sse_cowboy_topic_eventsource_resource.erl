%% Copyright (c) 2012, Peter Morgan <peter.james.morgan@gmail.com>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(sse_cowboy_topic_eventsource_resource).
-behaviour(cowboy_http_handler).
-export([init/3,
	 handle/2,
	 terminate/2]).

-record(state, {path, handler, event_manager, timeout, id = 1}).

init({tcp, http} = Protocol, Req, Args) ->
    init(Protocol, Req, Args, #state{}).

init(Protocol, Req, [{timeout, Timeout} | T], State) ->
    init(Protocol, Req, T, State#state{timeout = Timeout});
init(_, R1, [], State) ->
    sse_monitoring:increment_counter(eventsource_connections),
    {Path, R2} = cowboy_http_req:path_info(R1),
    EventManager = sse_hierarchy:event_manager(Path),
    Id = {emitter, self()},
    Handler = {sse_hierarchy_http_eventsource_handler, Id},
    sse_hierarchy_event:add_handler(EventManager, Handler, [Id]),
    {ok, R2, State#state{path = Path, handler = Handler, event_manager = EventManager}}.

handle(R1, State) ->
    Headers = [{'Content-Type', <<"text/event-stream">>},
	       {'Cache-Control', <<"no-cache">>}],
    {ok, R2} = cowboy_http_req:chunked_reply(200, Headers, R1),
    handle_loop(replay(R2, State), State).

replay(R1, State) ->
    case cowboy_http_req:header(<<"Last-Event-Id">>, R1) of
	{undefined, R2} ->
	    R2;
	{Value, R2} ->
	    {LastEventId, []} = string:to_integer(binary_to_list(Value)),
	    replay(LastEventId, R2, State)
    end.

replay(LastEventId, R1, #state{path = Path}) when is_integer(LastEventId) andalso LastEventId > 0 ->
    case sse_hierarchy:values(Path) of
	{ok, Events} ->
	    replay_events(LastEventId, R1, Events);
	_ ->
	    R1
    end.

replay_events(LastEventId, R1, Events) ->
    replay_event(R1, events_after(LastEventId, Events)).

replay_event(R1, []) ->
    R1;
replay_event(R1, [{Id, Value} | T]) ->
    case cowboy_http_req:chunk(format(Id, Value), R1) of
	ok ->
	    replay_event(R1, T);
	{error, _} ->
	    R1
    end.
    

events_after(LastEventId, Events) ->
    lists:reverse(lists:takewhile(fun({Id, _}) -> Id > LastEventId end, Events)).
    

handle_loop(Req, #state{event_manager = EventManager, handler = Handler, timeout = Timeout} = State) ->
    receive
	shutdown ->
	    sse_hierarchy_event:delete_handler(EventManager, Handler),
	    {ok, Req, State};
	
	{cowboy_http_req, resp_sent} ->
	    handle_loop(Req, State);
	
	{event, {update, _, Id, Value}} ->
	    case cowboy_http_req:chunk(format(Id, Value), Req) of
		{error, closed} ->
		    sse_hierarchy_event:delete_handler(EventManager, Handler),
		    sse_monitoring:increment_counter(eventsource_outbound_messages_error_closed),
		    {ok, Req, State};
		
		ok ->
		    sse_monitoring:increment_counter(eventsource_outbound_messages_sent_ok),
		    handle_loop(Req, State)
	    end

    after Timeout ->
	    case cowboy_http_req:chunk(io_lib:format(":~n~n", []), Req) of
		{error, closed} ->
		    sse_hierarchy_event:delete_handler(EventManager, Handler),
		    sse_monitoring:increment_counter(eventsource_outbound_ping_error_closed),
		    {ok, Req, State};
		
		ok ->
		    sse_monitoring:increment_counter(eventsource_outbound_ping_sent_ok),
		    handle_loop(Req, State)
	    end
    end.

format(Id, Value) ->
    format(Id, Value, proplists:get_value(data, Value), proplists:get_value(event, Value)).

format(Id, Value, undefined, undefined) ->
    format(Id, [{data, Value}]);
format(Id, _, Data, undefined) ->
    io_lib:format("id: ~p~ndata: ~s~n~n", [Id, jsx:to_json(Data, [])]);
format(Id, _, undefined, Event) ->
    io_lib:format("id: ~p~nevent: ~s~n~n", [Id, binary_to_list(Event)]);
format(Id, _, Data, Event) ->
    io_lib:format("id: ~p~nevent: ~s~ndata: ~s~n~n", [Id, binary_to_list(Event), jsx:to_json(Data, [])]).



terminate(_Req, _State) ->
    sse_monitoring:decrement_counter(eventsource_connections),
    ok.
