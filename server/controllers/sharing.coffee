Sharing = require '../lib/sharing'
db = require('../helpers/db_connect_helper').db_connect()

# Creation of the sharing
module.exports.create = (req, res, next) ->
    # check if the information is available
    if not req.share?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        # get a hold on the information
        share = req.share

        # put the share document in the database
        db.save share, (err, res) ->
            if err?
                next err
            else
                next()


# Request a sharing to a remote target
module.exports.requestTarget = (req, res, next) ->
    if not req.share?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        share = req.share
        hostUrl = cozydb.api.getCozyDomain
        params =
            shareID: share.id
            desc: share.desc
            sync: share.isSync
            hostUrl: share.hostUrl

        for target in req.share.targets
            Sharing.notifiy target.url, params, next

# Answer from target about a sharing request
module.exports.answerRequest = (req, res, next) ->
    # Do not accept empty body
    if Object.keys(req.body).length == 0
        err = new Error 'Parameters missing'
        err.status = 400
        next err
    else
        Sharing.targetAnswer req, res, next

# Validate a sharing for a target that has accepted the request
module.exports.validate = (req, res, next) ->
    ### TODO update the sharing doc
        targets : login, pwd, url
    next()
    ###
