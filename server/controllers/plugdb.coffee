Plug = require '../lib/plug'
init = require '../lib/init'

module.exports.auth = (req, res, next) ->

    # First check the init state
    Plug.isInit (err, isInit) ->
        console.log 'err : ' + JSON.stringify err
        console.log 'is init : ' + isInit
        # If an error is received, PlugDB is not init
        if err?
            Plug.init (err) ->
                #TODO: deal with plug errors 
                init.addSharingRules (err) ->
                    log.error err if err?
                    init.insertSharesPlugDB (err) ->
                        log.error err if err?
                res.send 200, 'ok'

        # If isInit is true, ask the fp
        else
            Plug.authFP (err, authID) ->
                if err?
                    res.sendStatus 500, error: err
                else if not authID?
                    res.send 401
                else
                    res.send 200, authID

module.exports.isAuth = (req, res, next) ->
    Plug.isInit (err, isInit) ->
        if err?
            res.send 500, error: 'PlugDB internal error'
        else
            console.log 'is init : ' + JSON.stringify isInit
            res.send 200, isAuth: isInit



###
if process.env.USE_PLUGDB
    #plugdb
    init.initPlugDB (err) ->
        log.error err if err?
        #sharing rules
        init.addSharingRules (err) ->
            log.error err if err?
            init.insertSharesPlugDB (err) ->
                log.error err if err?
###
