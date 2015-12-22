Sharing = require '../lib/sharing'
async = require 'async'
access = require './access'

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

# Send a sharing request for each target defined in the share object
module.exports.requestTarget = (req, res, next) ->
    if not req.share?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        share = req.share
        params =
            shareID: share.id
            desc: share.desc
            sync: share.isSync
            hostUrl: share.hostUrl

        # Notify each target
        async.each share.targets, (target, callback) ->
             Sharing.notifyTarget target.url, params, (err) ->
                callback err
        , (err) ->
            return next err if err?
            res.send 200, success: true
    
# Create access if the sharing answer is yes, remove the UserSharing doc otherwise.
# Send the answer to the host   
module.exports.sendAnswer = (req, res, next) ->

    ### Params must contains : 
    id (usersharing)
    shareID
    accepted
    targetUrl
    docIDs
    hostUrl
    ###

    params = req.params
    answer = 
        params.shareID
        params.url
        params.accepted

    # Create an access is the sharing is accepted
    if answer.accepted is yes
        createUserAccess params, (err, data) ->
            return next err if err?

            answer.pwd = data.password
            Sharing.answerHost params.hostUrl, answer, next
    # Delete the associated doc if the sharing is refused
    else
        db.remove params.id, (err, res) ->
            return next err if err?
            Sharing.answerHost params.hostUrl, answer, next

# Create an access for a user on a given share
createUserAccess = (userSharing, callback) ->

    access =
        login: userSharing.shareID
        password: randomString 32
        app: userSharing.id
        permissions: userSharing.docIDs

    access.create, access, (err, result, body) ->
        return callback(err) if err?
        data =
            password: access.password
            login: userSharing.shareID
            permissions: access.permissions
        # Return access to user
        callback null, data

# Validate a sharing for a target that has accepted the request
module.exports.validateTarget = (req, res, next) ->
    ### TODO update the sharing doc

    the received answer is : 
    answer {
        shareID: xxx
        url: xxx
        accepted: true
        pwd: xxx
    }

    if the answer.accepted is false, remove the target

    [...]
    
    req.share = share
    req.target = target #We need to know which target has been validated (see replicate)
    next()

    ###

module.exports.replicate = (req, res, next) ->

    share = req.share
    target = req.target

    # Replicate on the validated target
    if target.pwd?
        params = 
            url: target.url
            login: share.id
            pwd: target.url
            docIDs: share.docIDs
            isSync: share.isSync
        Sharing.replicateDocs params, (err) ->
            return next err if err?
            res.send 200, success: true
