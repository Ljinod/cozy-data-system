Sharing = require '../lib/sharing'

module.exports.answerRequest = (req, res, next) ->
    # Do not accept empty body
    if Object.keys(req.body).length == 0
        err = new Error 'parameters missing'
        err.status = 400
        next err
    else
        Sharing.targetAnswer req, res, next
