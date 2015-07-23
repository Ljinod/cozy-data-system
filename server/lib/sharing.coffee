plug = require './plug'
db = require('../helpers/db_connect_helper').db_connect()
async = require 'async'

# Contains all the sharing rules
rules = []

#Insert the doc into PlugDB
module.exports.mapDocOnInsert = (doc, id, callback) ->
    mapDocInRules doc, id, (err, results) ->
        if err or not results?
            callback err
        else
            async.series [
                (_callback) ->
                    # There is a doc result
                    if results[0]
                        plug.insertDoc results[0].docid, results[0].userDesc, (err) ->
                            if err? then callback err else callback null, results[0].id
                    else
                        callback null
                ,
                (_callback) ->
                    # There is an user result
                    if results[1]
                        plug.insertUser results[1].docid, results[1].userDesc, (err) ->
                            if err? then callback err else callback null, results[1].id
                    else
                        callback null
            ],
            (err, results) ->
                callback err, results
            

#Select doc into PlugDB
module.exports.selectDocPlug = (id, callback) ->
	plug.selectSingleDoc id, (err, tuple) ->
		callback err, tuple

#Select user into PlugDB
module.exports.selectUserPlug = (id, callback) ->
    plug.selectSingleUser id, (err, tuple) ->
        callback err, tuple


mapDocInRules = (doc, id, callback) ->
    rules.forEach (rule) ->
        console.log 'rule : ' + JSON.stringify rule
        async.parallel [
            (_callback) ->
                console.log 'doc : ' + JSON.stringify doc
                #convertDoc = doc.toString().replace("/\/", "");
                mapDoc doc, id, rule.filterDoc, (filteredDoc) ->
                    if filteredDoc then console.log 'doc maped !! ' + JSON.stringify filteredDoc
                    _callback null, filteredDoc
            ,
            (_callback) ->
                #convertDoc = doc.toString().replace("/\/", "");
                mapDoc doc, id, rule.filterUser, (filteredUser) ->
                    if filteredUser then console.log 'user maped !! ' + JSON.stringify filteredUser
                    _callback null, filteredUser
                
        ], 
        (err, results) ->
            if results[0]? || results[1]?
                console.log 'got a mapping !! ' + JSON.stringify results
            callback err, results
        

        

#Generic map : evaluate the rule in the filter against the doc
mapDoc = (doc, docid, filter, callback) ->
    console.log 'eval ' + JSON.stringify filter.rule + ' for the doc ' + JSON.stringify doc
    if eval filter.rule
        user_desc = if filter.userDesc then eval filter.userDesc 
        callback {docid, user_desc}
    else
        callback null


module.exports.createRule = (doc, callback) ->



module.exports.deleteRule = (doc, callback) ->
module.exports.updateRule = (doc, callback) ->

saveRule = (rule, callback) ->
    name = rule.name
    filterDoc = rule.filterDoc
    filterUser = rule.filterUser
    rules.push {name, filterDoc, filterUser}

#Called on the DS initialization
module.exports.initRules = (callback) ->
    db.view 'sharingRules/all', (err, rules) ->
        return callback new Error("Error in view") if err?
        rules.forEach (rule) ->
            saveRule rule
        callback()
