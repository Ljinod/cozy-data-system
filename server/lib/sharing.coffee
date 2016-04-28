db = require('../helpers/db_connect_helper').db_connect()
utils = require '../helpers/utils'
async = require 'async'
request = require 'request-json'
log = require('printit')
    prefix: 'sharing'


# Get the Cozy url
getDomain = (callback) ->
    db.view 'cozyinstance/all', (err, instance) ->
        return callback err if err?

        if instance?[0]?.value?.domain?
            domain = instance[0].value.domain
            domain = "https://#{domain}/" if not (domain.indexOf('http') > -1)
            callback null, domain
        else
            callback null

# Retrieve the domain if the url is not set, to avoid
# unacessary call and potential domain mismatch on the target side
checkDomain = (url, callback) ->
    unless url?
        # Get the cozy url to let the target knows who is the sender
        getDomain (err, domain) ->
            if err? or not domain?
                callback new Error 'No instance domain set'
            else
                callback err, domain
    else
        callback null, url


# Utility function to handle notifications responses
handleNotifyResponse = (err, result, body, callback) ->
    if err?
        callback err
    else if not result?.statusCode?
        err = new Error "Bad request"
        err.status = 400
        callback err
    else if body?.error?
        err = body
        err.status = result.statusCode
        callback err
    else if result?.statusCode isnt 200
        err = new Error "The request has failed"
        err.status = result.statusCode
        callback err
    else
        callback()


# Send a notification to a recipient url on the specified path
# Params must at least contain:
#   recipientUrl -> the url of the target
# A successful request is expected to return a 200 HTTP status
module.exports.notifyRecipient = (path, params, callback) ->
    # Get the domain if not already set
    checkDomain params.sharerUrl, (err, domain) ->
        return callback err if err?

        params.sharerUrl = domain
        remote = request.createClient params.recipientUrl
        remote.post path, params, (err, result, body) ->
            handleNotifyResponse err, result, body, callback


# Send a notification to a recipient url on the specified path
# Params must at least contain:
#   sharerUrl -> the url of the sharer
# A successful request is expected to return a 200 HTTP status
module.exports.notifySharer = (path, params, callback) ->
    # Get the domain if not already set
    checkDomain params.recipientUrl, (err, domain) ->
        return callback err if err?

        params.recipientUrl = domain
        remote = request.createClient params.sharerUrl
        remote.post path, params, (err, result, body) ->
            handleNotifyResponse err, result, body, callback


# Replicate documents to the specified target
# Params must contain:
#   id         -> the Sharing id, used as a login
#   target     -> contains the url and the token of the target
#   docIDs     -> the ids of the documents to replicate
#   continuous -> [optionnal] if the sharing is synchronous or not
module.exports.replicateDocs = (params, callback) ->
    if utils.hasEmptyField params, ["target", "docIDs", "id"]
        err = new Error 'Parameters missing'
        err.status = 400
        callback err
    else
        # Add the credentials in the url
        auth = "#{params.id}:#{params.target.token}"
        url = params.target.recipientUrl.replace "://", "://#{auth}@"

        replication =
            source: "cozy"
            target: url + "/services/sharing/replication/"
            continuous: params.continuous or false
            doc_ids: params.docIDs

        db.replicate replication.target, replication, (err, body) ->
            if err? then callback err
            else if not body.ok
                err = new Error "Replication failed"
                callback err
            else
                # The _local_id field is returned only if continuous
                callback null, body._local_id


# Interrupt the running replication
module.exports.cancelReplication = (replicationID, callback) ->
    unless replicationID?
        err = new Error 'Parameters missing'
        err.status = 400
        callback err
    else
        cancel =
            replication_id: replicationID
            cancel: true

        db.replicate '', cancel, (err, body) ->
            if err?
                callback err
            else if not body.ok
                err = "Cancel replication failed"
                callback err
            else
                callback()
