should  = require('chai').Should()
helpers = require './helpers'
sinon   = require 'sinon'

Sharing = require '../server/lib/sharing' # stub `notifyRecipient`

db      =
    require("#{helpers.prefix}server/helpers/db_connect_helper").db_connect()
client  = helpers.getClient()


# helpers
cleanRequest = ->
    delete @body
    delete @res


describe 'Share document tests: ', ->

    # Clear db and create a new one
    before helpers.clearDB db

    # Populate the db with an event
    before (done) ->
        data =
            created         : "2016-04-27T07:45:19.678Z"
            description     : "Rendez-vous"
            details         : "Meet russian spy"
            docType         : "event"
            end             : "2016-04-27T09:00:00.000Z"
            lastModification: "2016-04-26T07:45:19.678Z"
            place           : "Tomorrow never dies"
            related         : null
            start           : "2016-04-27T08:00:00.000Z"
            tags            : ["mi6"]
        db.save '007', data, done

    # Create a test application without 'sharing' permission
    before (done) ->
        data =
            app        : 1
            docType    : 'Access'
            login      : 'app_without_sharing'
            permissions:
                Event: description: 'Create and edit event'
            token      : 'token_without_sharing'
        db.save '101', data, done

    # Create a test application with 'sharing' permission
    before (done) ->
        data =
            app        : 2
            docType    : 'Access'
            login      : 'app_with_sharing'
            permissions:
                Event   : description: 'Create and edit event'
                Sharing : description: 'Share document with friends'
            token      : 'token_with_sharing'
        db.save '102', data, done

    # Start tests environment
    before helpers.startApp
    # Stop tests environment when tests are done
    after  helpers.stopApp

    # Expected sharing request, desc is optionnal
    sharingRequest =
        desc      : "New mission order"
        rules     : [{id: '007', docType: 'event'}]
        targets   : [{recipientUrl: 'james-bond@mi6.cozy.uk'}]
        continuous: false


    describe 'check sharing permission: ', ->

        before cleanRequest

        it 'When a request is made without sharing permission', (done) ->
            client.setBasicAuth 'app_without_sharing', 'token_without_sharing'
            client.post 'services/sharing/', sharingRequest, (err, res, body) =>
                @body = body
                @err  = err
                @res  = res
                done()

        it 'Then the application is not authorized', (done) ->
            should.not.exist @err
            @body.error.should.deep.equal "Application is not authorized"
            @res.statusCode.should.equal 403
            done()


    describe 'send sharing request', ->

        before cleanRequest

        # We need to stub the `notifyRecipient` module: it is going to send a
        # request on a route of the proxy which does not exist yet.
        stubNotifyRecipient = {}
        before (done) ->
            stubNotifyRecipient = sinon.stub Sharing, "notifyRecipient",
                (path, request, callback) =>
                    @shareID = request.shareID
                    callback()
            done()

        after (done) ->
            stubNotifyRecipient.restore()
            done()


        it 'When a request is made with sharing permission', (done) ->
            client.setBasicAuth 'app_with_sharing', 'token_with_sharing'
            client.post 'services/sharing/', sharingRequest, (err, res, body) =>
                @body = body
                @err  = err
                @res  = res
                done()

        it 'Then no error is returned', (done) ->
            should.not.exist @err
            should.exist @shareID
            @res.statusCode.should.equal 200
            done()


    describe 'delete sharing', ->

        before cleanRequest

        it 'When I send a delete request', (done) ->
            client.delete "services/sharing/#{@shareID}", (err, res, body) =>
                @body = body
                @err  = err
                @res  = res
                done()


