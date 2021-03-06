fs = require "fs"
path = require "path"
util = require "util"

restify = require "restify"
restler = require "restler"
async = require "async"
open = require "open"

paths = require "./paths"
DeployConverter = require "./DeployConverter"
Login = require "./Login"

Help = require "./Help"

class Deploy
  constructor: (@options={})->
    @cloudConfig = JSON.parse(fs.readFileSync(paths.application.configs.cloud, "utf8")) if fs.existsSync paths.application.configs.cloud

    @converter = new DeployConverter paths.application.configs.application

    @client = restify.createJsonClient
      # url: 'https://appgyver-staging.herokuapp.com'
      url: 'https://anka.appgyver.com'

  uploadToCloud: (callback=->)->
    @client.basicAuth Login.currentAccessToken(), 'X'

    @uploadApplicationJSON ()=>
      @uploadApplicationZip ()=>
        @updateConfigurationFile(callback)

  uploadApplicationJSON: (callback)->
    # util.log "Updating application configuration"
    util.log "Uploading Application to cloud"

    @app = @converter.applicationCloudSchemaRepresentation()

    if fs.existsSync paths.application.configs.cloud
      # util.log "Application has been deployed before"
      cloudConfig = JSON.parse fs.readFileSync(paths.application.configs.cloud, 'utf8')
      @app.id = cloudConfig.id
      # util.log "Using cloud ID: #{cloudConfig.id}"

    # util.log "Uploading #{JSON.stringify(@app)}"

    requestData =
      application: @app

    restifyCallback = (err, req, res, obj)=>
      # util.log "RECEIVED APPJSON SYNC RESPONSE"
      # util.log "err: #{util.inspect(err)}"
      # util.log "req: #{util.inspect(req)}"
      # util.log "res: #{util.inspect(res)}"
      # util.log "obj: #{util.inspect(obj)}"

      unless err
        # util.log "RECEIVED APPJSON SYNC SUCCESS"
        @cloudApp = obj
        callback()
      else
        # util.log "RECEIVED APPJSON SYNC FAILURE"
        # util.log "err: #{util.inspect(err)}"
        # util.log "obj: #{util.inspect(obj)}"
        process.exit 1

    if @app.id?
      # util.log "PUT"
      @client.put "/studio_api/applications/#{@app.id}", requestData, restifyCallback
    else
      # util.log "POST"
      @client.post "/studio_api/applications", requestData, restifyCallback

  uploadApplicationZip: (callback)->
    sourcePath = paths.temporaryZip
    # util.log "Updating application build from #{sourcePath} to #{@cloudApp.custom_code_zip_upload_url}"
    # util.log "key #{@cloudApp.custom_code_zip_upload_key}"

    params =
      success_action_status: "201"
      utf8: ""
      key: @cloudApp.custom_code_zip_upload_key
      acl: @cloudApp.custom_code_zip_upload_acl
      policy: @cloudApp.custom_code_zip_upload_policy
      signature: @cloudApp.custom_code_zip_upload_signature
      AWSAccessKeyId: @cloudApp.custom_code_zip_upload_access_key
      file: restler.file(
        sourcePath, # source path
        "custom_code.zip", # filename
        fs.statSync(sourcePath).size, # file size
        "binary", # file encoding
        'application/octet-stream') # file content type

    uploadRequest = restler.post @cloudApp.custom_code_zip_upload_url, { multipart: true, data:params }
    uploadRequest.on 'success', ()=>
      # util.log "Updated application build"
      callback()

  updateConfigurationFile: (callback)->
    # util.log "Updating #{paths.application.configs.cloud}"

    config =
      id: @cloudApp.id
      identification_hash: @cloudApp.identification_hash

    fs.writeFileSync paths.application.configs.cloud, JSON.stringify(config)

    util.log "Deployment complete"

    Help.deployCompleted()

    open "http://share.appgyver.com/?id=#{config.id}&hash=#{config.identification_hash}"

    callback()

module.exports = Deploy
