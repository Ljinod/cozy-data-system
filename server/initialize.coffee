log = require('printit')
    prefix: 'init'

module.exports = (app, server, callback) ->
    feed = require './lib/feed'
    feed.initialize server

    init = require './lib/init'
    init.removeDocWithoutDocType (err) ->
        log.error err if err?
        init.removeLostBinaries (err) ->
            log.error err if err?
            init.addThumbs (err) ->
                log.error err if err?
                # Patch: 24/03/15
                init.addAccesses (err) ->
                    log.error err if err?
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
            callback app, server if callback?
