-module(impel_webmachine_nodes_resource).

-export([init/1,
	 content_types_provided/2,
	 to_atom/2]).

-include_lib("webmachine/include/webmachine.hrl").

init([]) ->
    {ok, []}.


content_types_provided(ReqData, Context) ->
    {[{"application/atom+xml", to_atom}], ReqData, Context}.


to_atom(ReqData, State) ->
    {{stream, stream_atom(ReqData, State)}, ReqData, State}.

stream_atom(ReqData, State) ->
    {iolist_to_binary([<<"<?xml version=\"1.0\" encoding=\"utf-8\"?>">>,
		       <<"<feed xmlns=\"http://www.w3.org/2005/Atom\">">>,
		       <<"<title>Example Feed</title>">>,
		       io_lib:format("<link href=\"~s~s/nodes/\" rel=\"self\"/>", ph(ReqData)),
		       io_lib:format("<link href=\"~s~s/\"/>", ph(ReqData))
		      ]), stream_atom_entry(ReqData, State)}.

stream_atom_entry(ReqData, State) ->
    fun() ->
	    {ok, Children} = impel_hierarchy:children(),
	    stream_atom_entry(ReqData, State, Children)
    end.


stream_atom_entry(ReqData, State, [H | T]) ->
    {iolist_to_binary([<<"<entry>">>,
		       title(H),
		       io_lib:format("<link href=\"~s~s/node/~s\"/>", ph(ReqData) ++ [impel_hierarchy:key(H)]),
		       io_lib:format("<link rel=\"alternate\" type=\"text/event-stream\" href=\"~s~s/node/~s/live\"/>", ph(ReqData) ++ [impel_hierarchy:key(H)]),
		       io_lib:format("<id>urn:tag:nodes.example.com,~s/~s</id>", [ymd(impel_hierarchy:created(H)), impel_hierarchy:key(H)]),
		       updated(H),
		       <<"</entry>">>]),
		      fun() -> stream_atom_entry(ReqData, State, T) end};
stream_atom_entry(_, _, []) ->
    {<<"</feed>">>, done}.

ph(ReqData) ->
    [protocol(ReqData), host(ReqData)].

title(L) ->
    io_lib:format("<title>~p</title>", [impel_hierarchy:key(L)]).

updated(L) ->
    [<<"<updated>">>,
     impel_atom:rfc3339(impel_hierarchy:updated(L)),
     <<"</updated>">>].


host(ReqData) ->
     wrq:get_req_header("host", ReqData).

protocol(_ReqData) ->
    "http://".

ymd({{Year, Month, Day}, _}) ->
    io_lib:format("~4..0w-~2..0w-~2..0w", [Year, Month, Day]).


    
