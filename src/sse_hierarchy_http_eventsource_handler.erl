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

-module(sse_hierarchy_http_eventsource_handler).
-behaviour(gen_event).
-export([init/1,
	 terminate/2,
	 handle_info/2,
	 handle_event/2]).

-record(state, {emitter}).

init(P) ->
    init(P, #state{}).

init([{emitter, Emitter} | T], State) ->
    init(T, State#state{emitter = Emitter});
init([], State) ->
    {ok, State}.

handle_event(Event, #state{emitter = Emitter} = S) ->
    Emitter ! {event, Event},
    {ok, S}.

terminate(remove_handler, _) ->
    ok.

handle_info({'EXIT', _, shutdown}, _) ->
    remove_handler.


