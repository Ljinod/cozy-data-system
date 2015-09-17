Sharing = require '../lib/sharing'

module.exports.answerRequest = (req, res, next) ->
    answer = req.body.answer

    if not answer?
        err = new Error 'parameters missing'
        err.status = 400
        return next err

    
