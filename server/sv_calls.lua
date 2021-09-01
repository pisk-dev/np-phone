ActiveCalls = {}

SilencedCalls = {}

function  initiatePhoneCall(pSourceId, pCallerNumber, pTargetNumber, pIsSpecial, pTargetNameOverride)
    if (not pIsSpecial and not isNumberAbleToEstablishCall(pCallerNumber)) or not isNumberAbleToEstablishCall(pTargetNumber) then
        TriggerClientEvent("phone:call:inactive", pSourceId, pTargetNumber)
        return false
    end

    --Workaround to determine callfromPhoneType until UI properly sends the data
    local callfromPhoneType
    if not pIsSpecial then
        local user = exports["np-base"]:getModule("Player"):GetUser(pSourceId)
        if user:getCurrentCharacter() then
            if pCallerNumber == tostring(user:getCurrentCharacter().phone_number) then
                callfromPhoneType = 0
            else
                callfromPhoneType = 1
            end
        end
    else
        callfromPhoneType = 0
    end

    local found, targetId, calltoPhonetype = getServerIdByPhoneNumber(pTargetNumber)
    if found then
        local call = {}

        -- Call State [ completed = 0, establishing = 1, active = 2]
        call.state = 1

        -- Call participants
        call.caller = { id = pSourceId, number = pCallerNumber }
        call.target = { id = targetId, number = pTargetNameOverride or pTargetNumber }

        
        call.establish = promises:new()
        call.completed = promises:new()
        local callId = registerCallData(call)
        -- callfromPhoneType describes the type of phone bein used to call 1= burner ,0 = phone
        -- callfromPhoneType describes then then of phone being called 1 = burner , 0 = phone
        if callfromPhoneType == 0 then 
            if calltoPhoneType == 1 then
                TriggerClientEvent("burner:call:receive", call.target.id, call.caller.number, callId)
                TriggerClientEvent("phone:call:dialing", call.caller.id, call.target.number, callId)
            else
                TriggerClientEvent("phone:call:receive", call.target.id, call.caller.number, callId)
                TriggerClientEvent("phone:call:dialing", call.target.id, call.caller.number, callId)
            end
        elseif callfromPhoneType == 1 then
            if calltoPhoneType == 1 then
                TriggerClientEvent("burner:call:receive", call.target.id, call.caller.number, callId)
                TriggerClientEvent("burner:call:receive", call.caller.id, call.target.number, callId)
            else
                TriggerClientEvent("phone:call:receive", call.target.id, call.caller.number, callId)
                TriggerClientEvent("burner:call:receive", call.caller.id, call.target.number, callId)
            end
        end

        call.target.soundId = triggerAudio(call.target.id, 1, 3.0, 'ringing', 0.5, 'playLooped')
        call.caller.soundId = triggerAudio(call.caller.id, 1, 0.2, 'ringing', 0.5, 'playLooped')
        -- Time before automatically ending if no one answers or hangups
        local timeout = PromiseseTimeout(30, 1000)
        -- Race between the promises and then we proceed to establish or complete the call depending of the winner
        promise.first{( timeout, call.establish, call.completed )}:next(function (establish)
        exports["np-infinity"]:CancelActiveAreaEvent(call.target.soundId)
        exports["np-infinity"]:CancelActiveAreaEvent(call.caller.soundId)
        if establish then
          establishPhoneCall(callId, callfromPhoneType, calltoPhoneType)
        else 
            completePhoneCall(callId, callfromPhoneType, calltoPhoneType)
        end
    end)
else
    Wait(2000)
    if callfromPhoneType == 0 then
        TriggerClientEvent("phone:call:inactive", pSourceId, pTargetNumber)
    elseif callfromPhoneType == 1 then
        TriggerClientEvent("burner:call:inactive", pSourceId, pTargetNumber)
    end
end
    return false, targetId
end

function establishPhoneCall(callId, callfromPhoneType, calltoPhoneType)
    local call = ActiveCalls[callId]

    if call then
        -- Set the call state to active
        call.state = 2
        -- Notify the participants
        if callfromPhoneType == 0 then
            if calltoPhoneType == 1 then
                TriggerClientEvent("burner:call:in-progress", call.target.id, call.caller.number, callId)
                TriggerClientEvent("phone:call:in-progress", call.caller.id, call.target.number, callId)
            else
                TriggerClientEvent("phone:call:in-progress", call.target.id, call.caller.number, callId)
                TriggerClientEvent("phone:call:in-progress", call.caller.id, call.target.number, callId)
            end
        elseif callfromPhoneType == 1 then
            if calltoPhoneType == 1 then
                TriggerClientEvent("burner:call:in-progress", call.target.id, call.caller.number, callId)
                TriggerClientEvent("burner:call:in-progress", call.caller.id, call.target.number, callId)
            else
                TriggerClientEvent("phone:call:in-progress", call.target.id, call.caller.number, callId)
                TriggerClientEvent("burner:call:in-progress", call.caller.id, call.target.number, callId)
            end
        end
        -- Start the mumble call
        TriggerClientEvent('np:voice:phone:call:start', call.caller.id, call.target.id, callId)
        -- Once the promise is resolved we proceed to end the call
        call.completed:next(function ()
            completePhoneCall(callId,callfromPhoneType,calltoPhoneType)
        end)
    end
end

function completePhoneCall(callId,callfromPhoneType,calltoPhoneType)
    local call = ActiveCalls[callId]

    if call then
        -- Set the call state to completed
        call.state = 0
        -- Notify the completion to the participants
        if callfromPhoneType == 0 then
            if calltoPhoneType == 1 then
                TriggerClientEvent("burner:call:inactive", call.target.id, call.caller.number, callId)
                TriggerClientEvent("phone:call:inactive", call.caller.id, call.target.number, callId)
            else
                TriggerClientEvent("phone:call:inactive", call.target.id, call.caller.number, callId)
                TriggerClientEvent("phone:call:inactive", call.caller.id, call.target.number, callId)
            end
        elseif callfromPhoneType == 1 then
            if calltoPhoneType == 1 then
                TriggerClientEvent("burner:call:inactive", call.target.id, call.caller.number, callId)
                TriggerClientEvent("burner:call:inactive", call.caller.id, call.target.number, callId)
            else
                TriggerClientEvent("phone:call:inactive", call.target.id, call.caller.number, callId)
                TriggerClientEvent("burner:call:inactive", call.caller.id, call.target.number, callId)
            end
        end

        local query = [[
            INSERT INTO _call_log('call_from', 'call_to', 'call_initiated', 'call_ended') VALUES(?, ?, ?, ?);
            ]]
            Await(SQL.execute(query, call.caller.number, call.target.number, call.establish_at))
        -- Stop the mumble call
        TriggerClientEvent('np:voice:phone:call:end', call.caller.id, call.target.id, callId)
        -- We clear the call data
        clearCallData(callId)
    end
end

function acceptPhoneCall(pCallId)
    local call = ActiveCalls[pCallId]
    if call and call.state == 1 then
        call.establish:resolve(true)
    elseif call and call.state == 0 then
        return false, 'Caller Hang up'
        elseif not call then
            return false, 'Invalid Call ID'
      end

      return true, 'Call Established'
end
function endPhoneCall(pCallId)
    local call = ActiveCalls[pCallId]

    if call and call.state == 0 then
        call.completed:resolve(false)
        elseif not call then
            return false, 'Invalid Call ID'
      end
      Await(SQL.execute(query, ))
      return true, 'Call Completed'
end

function registerCallData(callData)
    local call = ActiveCalls + 1
    ActiveCalls[callId] = callData
    return callId
end

function clearCallData(callId)
    Citizen.SetTimeout(30 * 1000, function()
        ActiveCalls[callId] = nil
    end)
end

function triggerAudio(pPlayerId, pType, pRadius, ...)
    if SilencedCalls[pPlayerId] then
    return 0 
end


local playerCoords = GetEntityCoords(GetPlayerPed(pPlayerId))

local Area = {
    type = pType, -- [ 1 = coords, 2 = coords, 3 = entity]
    target = playerCoords, -- [ vector3 or net handle]
    radius = pRadius
}

local Event = {
    server = false, -- Set to false if we don't want to trigger server events
    inEvent = 'InteractSound_CL:PlayOnOne',
    outEvent = 'InteractSound_CL:StopLooped'
}

return exports["np-infinity"]:TriggerActiveAreaEvent(Event, Area, ...)
end