application = module.exports = (callback) ->

    americano = require 'americano'
    initialize = require './server/initialize'
    errorMiddleware = require './server/middlewares/errors'

    # PlugDB API
    plugdb = require './server/lib/plug'

    # Initialize database
    # * Create cozy database if not exists
    # * Add admin database if not exists
    # * Initialize request view (_design documents)
    # * Initialize application accesses
    db = require './server/lib/db'
    db ->
        options =
            name: 'data-system'
            port: process.env.PORT or 9101
            host: process.env.HOST or "127.0.0.1"
            root: __dirname

        # Start data-system server
        americano.start options, (app, server) ->
            app.use errorMiddleware
            # Clean lost binaries
            initialize app, server, callback

        # So the program will not close instantly
        process.stdin.resume()

        exitHandler = (options, err) ->
            console.log 'clean' if options.cleanup
            console.log err.stack if err

            console.log 'is init : ' + plugdb.isInit()
            if plugdb.isInit() && options.exit
                plugdb.close (err) ->
                    console.log 'PlugDB closed' if not err

            process.exit() if options.exit

        # do something when app is closing
        process.on 'exit', exitHandler.bind null, {cleanup:true}
        # catches ctrl+c event
        process.on 'SIGINT', exitHandler.bind null, {exit:true}
        #catches uncaught exceptions
        process.on 'uncaughtException', exitHandler.bind null, {exit:true}

if not module.parent
    application()
