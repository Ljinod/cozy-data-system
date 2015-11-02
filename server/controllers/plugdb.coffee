Plug = require '../lib/plug'

module.exports.auth = (req, res, next) ->
    Plug.authFP (err, authID) ->
        if err?
            res.send 500, error: err
        else if not authID?
            res.send 401
        else
            res.send 200, authID
