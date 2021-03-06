
# Jaspreet Randhawa (jsr15) and Jinsung Ha (jsh114) 

defmodule Replica do

    def start config, database, monitor do
        leaders = receive do
            {:bind, leaders} ->
                leaders
            end
        slot_in = 1
        slot_out = 1
        requests = MapSet.new
        proposals = Map.new
        decisions = Map.new

        next leaders, database, monitor, slot_in, slot_out, requests, proposals, decisions, config
    end # start

    def next leaders, database, monitor, slot_in, slot_out, requests, proposals, decisions, config do
        receive do
        {:client_request, c} ->
            send monitor, {:client_request, config.server_num}
            requests = MapSet.put requests, c
        {:decision, s, c} ->
            #IO.puts "decisions"
            decisions = Map.put decisions, s, c
            {proposals, requests, slot_out} = apply_decisions decisions, proposals, requests, slot_out, database, monitor, config
        end #_receive
        {slot_in, requests, proposals} = propose leaders, slot_in, slot_out, MapSet.to_list(requests), proposals, decisions, config
        requests = MapSet.new requests
        next leaders, database, monitor, slot_in, slot_out, requests, proposals, decisions, config
    end # next

    def apply_decisions decisions, proposals, requests, slot_out, database, monitor, config do
        #IO.puts "apply decisions"
        case decisions[slot_out] do
        nil -> 
            {proposals, requests, slot_out}
        d_command ->
            p_command = proposals[slot_out] 
            if p_command != nil do
                proposals = Map.delete proposals, slot_out
                if d_command != p_command do
                    requests = MapSet.put requests, p_command
                end #_if
            end #_if
            slot_out = perform d_command, decisions, slot_out, database, monitor, config
            apply_decisions decisions, proposals, requests, slot_out, database, monitor, config
        end #_case
    end # apply_decisions

    def perform_helper n, slot_out, decisions, d_command do
        c = decisions[n]
        cond do
        n >= slot_out ->
            false
        c == d_command ->
            true
        true ->
            perform_helper n+1, slot_out, decisions, d_command
        end
    end

    def perform d_command, decisions, slot_out, database, monitor, config do
        slot_found = perform_helper 1, slot_out, decisions, d_command
        if not slot_found do
            {client, cid, op} = d_command
            send database, {:execute, op}
            send client, {:reply, cid, true}
        end #_if
        slot_out + 1
    end # perform

    def propose leaders, slot_in, slot_out, requests, proposals, decisions, config do
        cond do
        slot_in < slot_out + config.window and requests != [] ->
            c = decisions[slot_in]
            if c == nil do
                [request | requests] = requests
                proposals = Map.put proposals, slot_in, request
                for leader <- leaders, do: send leader, {:propose, slot_in, request}
            end #_if
            slot_in = slot_in + 1
            propose leaders, slot_in, slot_out, requests, proposals, decisions, config
        true ->
            {slot_in, requests, proposals}
        end #_cond
    end # propose
    
end # Replica

