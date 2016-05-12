Sharing = require '../lib/sharing'
async = require "async"
crypto = require "crypto"
util = require 'util'
log = require('printit')
    prefix: 'sharing'

libToken = require '../lib/token'
utils = require '../helpers/utils'
db = require('../helpers/db_connect_helper').db_connect()

TOKEN_LENGTH = 32


# Randomly generates a token.
generateToken = (length) ->
    return crypto.randomBytes(length).toString('hex')


# Returns the target position in the array
findTargetIndex = (targetArray, target) ->
    if targetArray? and targetArray.length isnt 0
        targetArray.map((t) -> t.recipientUrl).indexOf target.recipientUrl
    else
        return -1


# Add a shareID field for each doc specified in the sharing rules
addShareIDDocs = (rules, shareID, callback) ->
    async.eachSeries rules, (rule, cb) ->
        db.get rule.id, (err, doc) ->
            if err?
                cb err
            else
                doc.shareID = shareID
                db.merge rule.id, doc, (err, result) ->
                    cb err
    , (err) ->
        callback err


# Save the error in the sharing doc
saveErrorInTarget = (error, id, target, callback) ->
    if error?.message?
        db.get id, (err, doc) ->
            if err?
                callback err
            else
                i = findTargetIndex doc.targets, target
                doc.targets[i].error = error.message

                db.merge id, doc, (err, result) ->
                    callback err
    else
        callback()



# Add a shareID field for each doc specified in the sharing rules
addShareIDnDocs = (rules, shareID, callback) ->
    async.eachSeries rules, (rule, cb) ->
        db.get rule.id, (err, doc) ->
            if err?
                cb err
            else
                doc.shareID = shareID
                db.merge rule.id, doc, (err, result) ->
                    cb err
    , (err) ->
        callback err


# Creation of the Sharing document
#
# The structure of a Sharing document is as following.
# Note that the [generated] fields to not need to be indicated
# share {
#   id         -> [generated] the id of the sharing document.
#                 This id will sometimes be refered as the shareID
#   desc       -> [optionnal] a human-readable description of what is shared
#   rules[]    -> a set of rules describing which documents will be shared,
#                 providing their id and their docType
#   targets[]  -> an array containing the users to whom the documents will be
#                 shared. See below for a description of this structure
#   continuous -> [optionnal] boolean saying if the sharing is synchronous
#                 set at false by default
#                 The sync is one-way, from sharer to recipient
#   docType    -> [generated] Automatically set at 'sharing'
# }
#
# The target structure:
# target {
#   recipientUrl -> the url of the recipient's cozy
#   preToken     -> [generated] a token used to authenticate the target's answer
#   token        -> [generated] the token linked to the sharing process,
#                   sent by the recipient
#   repID        -> [generated] the id generated by CouchDB for the replication
# }
module.exports.create = (req, res, next) ->
    share = req.body

    # We need at least a target and a rule to initiate a share
    if utils.hasEmptyField share, ["targets", "rules"]
        err        = new Error "Body is incomplete"
        err.status = 400
        return next err

    # Each rule must have an id and a docType
    if utils.hasIncorrectStructure share.rules, ["id", "docType"]
        err        = new Error "Incorrect rule detected"
        err.status = 400
        return next err

    # Each target must have an url
    if utils.hasIncorrectStructure share.targets, ["recipientUrl"]
        err        = new Error "No url specified"
        err.status = 400
        return next err

    # The docType is fixed
    share.docType = "sharing"

    # Generate a preToken for each target
    for target in share.targets
        target.preToken = generateToken TOKEN_LENGTH

    # save the share document in the database
    db.save share, (err, res) ->
        if err?
            next err
        else
            share.shareID = res._id
            req.share = share
            next()


# Delete an existing sharing, on the sharer side
module.exports.deleteFromSharer = (req, res, next) ->
    if not req.params?.id?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        shareID = req.params.id

        # Get all the targets in the sharing document
        db.get shareID, (err, doc) ->
            if err?
                next err
            else
                share =
                    shareID: shareID
                    targets: doc.targets

                # remove the sharing document in the database
                db.remove shareID, (err, res) ->
                    return next err if err?
                    req.share = share
                    next()


# Delete a target from an existing sharing, on the sharer side
module.exports.deleteTargetFromSharer = (req, res, next) ->
    unless req.params?.id? and req.params?.target?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        shareID = req.params.id
        target = {recipientUrl: req.params.target}

        # Get the sharing document
        db.get shareID, (err, doc) ->
            if err?
                next err
            else
                # Remove the target
                i = findTargetIndex doc.targets, target
                if i < 0
                    err = new Error "Target not found"
                    err.status = 404
                    next err
                else
                    target = doc.targets[i]
                    doc.targets.splice i, 1

                    # Update the Sharing doc
                    db.merge shareID, doc, (err, result) ->
                        return next err if err?

                        share =
                            shareID: shareID
                            targets: [target]

                        req.share = share
                        next()


# Delete an existing sharing, on the recipient side
module.exports.deleteFromTarget = (req, res, next) ->
    if not req.params?.id?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        id = req.params.id
        # Get the recipient's sharing doc
        db.get id, (err, doc) ->
            if err?
                next err
            else
                # Revoke the access
                libToken.removeAccess doc, (err) ->
                    if err?
                        next err
                    else
                        # Remove the sharing doc
                        db.remove id, (err) ->
                            return next err if err?
                            req.share = doc
                            next()


# Send a sharing request for each target defined in the share object
# It will be viewed as a notification on the targets side
# Params must contains :
#   shareID    -> the id of the sharing process
#   rules[]    -> the set of rules specifying which documents are shared,
#                 with their docTypes.
#   targets[]  -> the targets to notify. Each target must have an url
#                 and a preToken
module.exports.sendSharingRequests = (req, res, next) ->
    share = req.share

    # Notify each target
    async.eachSeries share.targets, (target, callback) ->
        request =
            recipientUrl: target.recipientUrl
            preToken    : target.preToken
            shareID     : share.shareID
            rules       : share.rules
            desc        : share.desc

        log.info "Send sharing request to : #{request.recipientUrl}"

        url = target.recipientUrl
        path = "services/sharing/request"
        Sharing.notifyRecipient url, path, request, (err) ->
            saveErrorInTarget err, share.shareID, target, (error) ->
                if error? then callback error else callback err
    , (err) ->
        if err?
            next err
        else
            res.status(200).send success: true


# Send a sharing revocation for each target defined in the share object
# Params must contains :
#   shareID    -> the id of the sharing process
#   targets[]  -> the targets to notify. Each target must have an url
#                 and a token (or preToken if it has not answered)
module.exports.sendRevocationToTargets = (req, res, next) ->
    share = req.share

    # Notify each target
    async.eachSeries share.targets, (target, callback) ->
        revoke =
            recipientUrl: target.recipientUrl
            desc: "The sharing #{share.shareID} has been deleted"

        log.info "Send sharing revocation to the target #{revoke.recipientUrl}"

        # Add the credentials in the url
        # The password can be a token or preToken depending if the
        # target has answered the sharing request or not
        token = target.token or target.preToken
        auth = "#{share.shareID}:#{token}"
        url = revoke.recipientUrl.replace "://", "://#{auth}@"
        path = "services/sharing"

        Sharing.sendRevocation url, path, revoke, (err) ->
            saveErrorInTarget err, share.shareID, target, (error) ->
                if error? then callback error else callback err
    , (err) ->
        if err?
            next err
        else
            res.status(200).send success: true


# Send a sharing revocation to the sharer defined in the share object
# Params must contains :
#   shareID    -> the id of the sharing process
#   sharerUrl  -> the url of the sharer's cozy
#   token      -> the token used to authenticate the recipient
module.exports.sendRevocationToSharer = (req, res, next) ->
    share = req.share

    revoke =
        sharerUrl: share.sharerUrl
        desc: "The sharing target #{share.recipientUrl} has revoked itself"

    log.info "Send sharing revocation to the sharer #{revoke.sharerUrl}"

    # Add the credentials in the url
    token = share.token
    auth = "#{share.shareID}:#{token}"
    url = revoke.sharerUrl.replace "://", "://#{auth}@"
    path = "services/sharing/target"

    Sharing.sendRevocation url, path, revoke, (err) ->
        if err?
            next err
        else
            res.status(200).send success: true


# Create access if the sharing answer is yes, remove the Sharing doc otherwise.
#
# The access will grant permissions to the sharer, only on the documents
# specified in the sharing request.
# The shareID is then used as a login and a token is generated.
#
# Params must contains :
#   id           -> the id of the Sharing document, created when the sharing
#                   request was received
#   accepted     -> boolean specifying if the share was accepted or not
module.exports.handleRecipientAnswer = (req, res, next) ->

    share = req.body

    console.log JSON.stringify share

    # A correct answer must have the following attributes
    if utils.hasEmptyField share, ["id", "accepted"]
        err = new Error "Bad request: body is incomplete"
        err.status = 400
        return next err

    # Get the Sharing document thanks to its id
    db.get share.id, (err, doc) ->
        return next err if err?

        # The sharing is accepted : create an access and update the sharing doc
        if share.accepted

            access =
                login   : doc.shareID
                password: generateToken TOKEN_LENGTH
                id      : share.id
                rules   : doc.rules

            libToken.addAccess access, (err, accessDoc) ->
                return next err if err?

                doc.accepted = share.accepted
                db.merge share.id, doc, (err, result) ->
                    return next err if err?
                    req.share = doc
                    req.share.token = access.password
                    return next()

            # TODO : enforce the docType protection with the couchDB's document
            # update validation

        # The sharing is refused : delete the Sharing doc
        else
            db.remove share.id, (err, res) ->
                return next err if err?
                doc.accepted = false
                req.share = doc
                next()


# Send the answer to the emitter of the sharing request
#
# Params must contain:
#   shareID      -> the id of the Sharing document generated by the sharer
#   recipientUrl -> the url of the recipient's cozy
#   accepted     -> boolean specifying if the share was accepted or not
#   preToken     -> the token sent by the sharer to authenticate the receiver
#   token        -> the token generated by the receiver if the request was
#                   accepted
#   sharerUrl    -> the url of the sharer's cozy
module.exports.sendAnswer = (req, res, next) ->
    share = req.share

    answer =
        sharerUrl   : share.sharerUrl
        recipientUrl: share.recipientUrl
        accepted    : share.accepted
        token       : share.token

    log.info "Send sharing answer to : #{answer.sharerUrl}"

    # Add the credentials in the url
    auth = "#{share.shareID}:#{share.preToken}"
    url = answer.sharerUrl.replace "://", "://#{auth}@"

    Sharing.notifySharer url, "services/sharing/answer", answer,
    (err, result, body) ->
        if err?
            next err
        else
            res.status(200).send success: true


# Process the answer given by a target regarding the sharing request
# previously sent.
#
# Params must contain:
#   shareID      -> the id of the sharing request
#   recipientUrl -> the url of the recipient's cozy
#   accepted     -> boolean specifying if the share was accepted or not
#   preToken     -> the token sent by the sharer to authenticate the receiver
#   token        -> [conditionnal] token generated by the target, if accepted
module.exports.validateTarget = (req, res, next) ->

    answer = req.body

    # Check the structure of the answer
    if utils.hasEmptyField answer, ["shareID", "recipientUrl", "accepted",\
                                    "preToken"]
        err = new Error "Bad request: body is incomplete"
        err.status = 400
        return next err

    # Get the Sharing document thanks to its id
    db.get answer.shareID, (err, doc) ->
        return next err if err?

        # Get the answering target
        target = doc.targets.filter (t)-> t.recipientUrl is answer.recipientUrl
        target = target[0]

        unless target?
            err = new Error "#{answer.recipientUrl} not found for this sharing"
            err.status = 404
            return next err

        # The answer cannot be sent more than once
        if target.token?
            err = new Error "The answer for this sharing has already been given"
            err.status = 403
            return next err

        # Check if the preToken is correct
        if not target.preToken? or target.preToken isnt answer.preToken
            err = new Error "Unauthorized"
            err.status = 401
            return next err

        # The target has accepted the sharing : save the token
        if answer.accepted
            log.info "Sharing #{answer.shareID} accepted by
                #{target.recipientUrl}"

            target.token = answer.token
            delete target.preToken
        # The target has refused the sharing : remove the target
        else
            log.info "Sharing #{answer.shareID} denied by
                #{target.recipientUrl}"
            i = findTargetIndex doc.targets, target
            doc.targets.splice i, 1

        # Update the Sharing doc
        db.merge doc._id, doc, (err, result) ->
            return next err if err?

            # Add the shareID for each shared document
            addShareIDDocs doc.rules, doc._id, (err) ->
                return next err if err?

                # Params structure for the replication
                share =
                    target : target
                    doc    : doc

                req.share = share
                next()


# Replicate documents to the target url
# Params must contain:
#   doc        -> the Sharing document
#   target     -> contains the url and the token of the target
module.exports.replicate = (req, res, next) ->
    share = req.share

    # Replicate only if the target has accepted, i.e. gave a token
    if share.target.token?
        doc = share.doc
        target = share.target

        # Retrieve all the docIDs
        docIDs = (rule.id for rule in doc.rules)
        replicate =
            id          : doc._id
            target      : target
            docIDs      : docIDs
            continuous  : doc.continuous

        Sharing.replicateDocs replicate, (err, repID) ->
            if err?
                saveErrorInTarget err, doc._id, target, (error) ->
                    if error? then next error else next err
            # The repID is needed if continuous
            else if replicate.continuous and not repID?
                err = new Error "Replication error"
                err.status = 500
                saveErrorInTarget err, doc._id, target, (error) ->
                    if error? then next error else next err
            else
                log.info "Data successfully sent to #{target.recipientUrl}"

                # Update the target with the repID if the sharing is continuous
                if replicate.continuous
                    i = findTargetIndex doc.targets, target
                    doc.targets[i].repID = repID

                    db.merge doc._id, doc, (err, result) ->
                        return next err if err?

                        res.status(200).send success: true
                else
                    res.status(200).send success: true

    else
        res.status(200).send success: true


# Stop current replications for each specified target
# Params must contain:
#   targets[]  -> Each target must have an url,  a repID and a token
module.exports.stopReplications = (req, res, next) ->
    share = req.share

    # Cancel the replication for all the targets
    async.eachSeries share.targets, (target, cb) ->
        if target.repID?
            Sharing.cancelReplication target.repID, (err) ->
                cb err
        else
            cb()
    , (err) ->
        next err

