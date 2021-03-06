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

-module(sse_atom).
-export([to_atom/3]).
-export([join/1]).

to_atom(ReqData, State, Entries) ->
    to_atom(ReqData, State, [header(ReqData, State)], Entries).

to_atom(ReqData, State, A, []) ->
    lists:reverse([footer(ReqData, State) | A]);
to_atom(ReqData, State, A, [H | T]) ->
    to_atom(ReqData, State, [entry(ReqData, State, H) | A], T).

header(ReqData, _) ->
    Self = case cowboy_http_req:path_info(ReqData) of
	       {undefined, _} ->
		   <<"topics">>;
	       {Components, _} ->
		   join(Components)
	   end,
    [<<"<?xml version=\"1.0\" encoding=\"utf-8\"?>">>,
     <<"<feed xmlns=\"http://www.w3.org/2005/Atom\">">>,
     io_lib:format("<title>~s</title>", [Self]),
     io_lib:format("<link href=\"~s~s/~s\" rel=\"self\"/>", ph(ReqData) ++ [Self]),
     io_lib:format("<link href=\"~s~s/\"/>", ph(ReqData))].

entry(ReqData, State, Entry) ->
    Path = case cowboy_http_req:path_info(ReqData) of
	       {undefined, _} ->
		   [];
	       {Components, _} ->
		   Components
	   end,
    entry(ReqData, State, Entry, Path, sse_hierarchy:type(Entry)).

entry(ReqData, _, Entry, Path, branch) ->
    Topic = [join(Path ++ [sse_hierarchy:key(Entry)])],
    [<<"<entry>">>,
     title(Entry),
     io_lib:format("<link href=\"~s~s/topic/~s\" type=\"application/atom+xml\"/>", ph(ReqData) ++ Topic),
     io_lib:format("<id>urn:tag:~s,~s/~s</id>", [h(ReqData), ymd(sse_hierarchy:created(Entry)), sse_hierarchy:key(Entry)]),
     updated(Entry),
     <<"</entry>">>];
entry(ReqData, _, Entry, Path, leaf) ->
    Topic = [join(Path ++ [sse_hierarchy:key(Entry)])],
    [<<"<entry>">>,
     title(Entry),
     io_lib:format("<link href=\"~s~s/es/~s\" type=\"text/event-stream\"/>", ph(ReqData) ++ Topic),
     io_lib:format("<id>urn:tag:~s,~s/~s</id>", [h(ReqData), ymd(sse_hierarchy:created(Entry)), Topic]),
     updated(Entry),
     <<"</entry>">>].

footer(_, _) ->
    [<<"</feed>">>].

join(Items) ->
    join(Items, <<"/">>).

join([H1, H2 | T], Separator) ->
    [H1, Separator | join([H2 | T], Separator)];
join([H | T], Separator) ->
    [H | join(T, Separator)];
join([], _) ->
    [].



ph(ReqData) ->
    [protocol(ReqData), host(ReqData)].

h(ReqData) ->
    {Raw, _} = cowboy_http_req:raw_host(ReqData),
    Raw.

title(L) ->
    io_lib:format("<title>~s</title>", [sse_hierarchy:key(L)]).

updated(L) ->
    [<<"<updated>">>,
     rfc3339(sse_hierarchy:updated(L)),
     <<"</updated>">>].


host(R1) ->
    {Raw, R2} = cowboy_http_req:raw_host(R1),
    {Port, _} = cowboy_http_req:port(R2),
    host(Raw, Port).

host(Host, 80) ->
    Host;
host(Host, Port) ->
    binary_to_list(Host) ++ [":" | integer_to_list(Port)].


protocol(_ReqData) ->
    "http://".

ymd({{Year, Month, Day}, _}) ->
    io_lib:format("~4..0w-~2..0w-~2..0w", [Year, Month, Day]).

rfc3339({{Year, Month, Day}, {Hour, Minute, Second}}) ->
    io_lib:format("~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0wZ", [Year, Month, Day, Hour, Minute, Second]).
