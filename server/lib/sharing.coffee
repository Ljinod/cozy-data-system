plug = require './plug'
db = require('../helpers/db_connect_helper').db_connect()
async = require 'async'

# Contains all the sharing rules
rules = []

# Map the inserted document against all the sharing rules
# If one or several mapping are trigerred, the result {id, shareid, userParams}
# will be inserted in PlugDB as a Doc and/or a User
module.exports.mapDocOnInsert = (doc, id, callback) ->
    mapDocInRules doc, id, (err, mapResults) ->
        # mapResults : [ {docid, userid, shareid, userParams} ]
        if err
            callback err
        else
            async.map mapResults, insertResults, (err) ->
                console.log 'results : ' + JSON.stringify mapResults
                callback err, mapResults

# Insert the map result as a tuple in PlugDB, as a Doc and/or as a User
# mapResult : {docid, userid, shareid, userParams}
insertResults = (mapResult, callback) ->

    async.series [
        (_callback) ->
            # There is a doc result
            if mapResult.docid?
                plug.insertDoc mapResult.docid, mapResult.shareid, mapResult.userDesc, (err) ->
                    if not err? then console.log mapResult.docid + " inserted in PlugDB"
                    if err? then _callback err else _callback null
            else
                _callback null
        ,
        (_callback) ->
            # There is an user result
            if mapResult.user?
                plug.insertUser mapResult.docid, mapResult.shareid, mapResult.userDesc, (err) ->
                    if not err? then console.log mapResult.userid + " inserted in PlugDB"
                    if err? then _callback err else _callback null
            else
                _callback null
    ],
    (err) ->
        callback err


#Select doc into PlugDB
module.exports.selectDocPlug = (id, callback) ->
	plug.selectSingleDoc id, (err, tuple) ->
		callback err, tuple

#Select user into PlugDB
module.exports.selectUserPlug = (id, callback) ->
    plug.selectSingleUser id, (err, tuple) ->
        callback err, tuple


# For each rule, evaluates if the document is correctly filtered/mapped
# as a document and/or a user
mapDocInRules = (doc, id, callback) ->

    # Evaluate a rule for the doc
    evalRule = (rule, _callback) ->

        mapResult =
            docid: null
            userid: null
            shareid: null
            userParams: null

        # Save the result of the mapping
        saveResult = (id, shareid, userParams, isDoc) ->
            if isDoc then mapResult.docid = id else mapResult.userid = id
            mapResult.shareid = shareid
            mapResult.userParams = userParams

        filterDoc = rule.filterDoc
        filterUser = rule.filterUser

        # Evaluate the doc filter
        mapDoc doc, id, rule.id, filterDoc, (docMaped) ->
            if docMaped then console.log 'doc maped !! '
            saveResult id, rule.id, filterDoc.userParam, true if docMaped

            # Evaluate the user filter
            mapDoc doc, id, rule.id, filterUser, (userMaped) ->
                if userMaped then console.log 'user maped !! '
                saveResult id, rule.id, filterUser.userParam, false if userMaped

                if not mapResult.docid? && not mapResult.userid?
                    _callback null, null
                else
                    _callback null, mapResult

    # Evaluate all the rules
    # mapResults : [ {docid, userid, shareid, userParams} ]
    async.map rules, evalRule, (err, mapResults) ->
        # Convert to array and remove null results
        mapResults = Array.prototype.slice.call( mapResults )
        for i in [mapResults.length-1..0]
            mapResults.splice(i, 1) if mapResults[i] is null

        callback err, mapResults


# Generic map : evaluate the rule in the filter against the doc
mapDoc = (doc, docid, shareid, filter, callback) ->
    #console.log 'eval ' + JSON.stringify filter.rule + ' for the doc ' + JSON.stringify doc
    if eval filter.rule
        if filter.userDesc then ret = eval filer.userDesc else ret = true
        callback ret
    else
        callback false


module.exports.createRule = (doc, callback) ->

module.exports.deleteRule = (doc, callback) ->
module.exports.updateRule = (doc, callback) ->

saveRule = (rule, callback) ->
    id = rule._id
    name = rule.name
    filterDoc = rule.filterDoc
    filterUser = rule.filterUser
    rules.push {id, name, filterDoc, filterUser}

#Called on the DS initialization
module.exports.initRules = (callback) ->
    db.view 'sharingRules/all', (err, rules) ->
        return callback new Error("Error in view") if err?
        rules.forEach (rule) ->
            saveRule rule

        callback()
