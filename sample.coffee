############################################################################
#     Copyright (C) 2014-2015 by Vaughn Iverson
#     meteor-file-job-sample-app is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

# Both client and server

# Default collection name is 'fs'
myData = new FileCollection('images', {
   resumable: true,     # Enable the resumable.js compatible chunked file upload interface
   http: [
      { method: 'get', path: '/:_id', lookup: (params, query) -> return { _id: params._id }},
      { method: 'put', path: '/put/:_id', lookup: (params, query) -> return { _id: params._id }}
   ]}
)

myJobs = new JobCollection 'queue',
   idGeneration: 'MONGO'
   transform: (d) ->
      try
         res = myJobs.createJob d
      catch e
         res = d
      return res

Router.configure
   layoutTemplate: 'master'

Router.route '/', () ->
   this.redirect '/gallery'

Router.route '/gallery', () ->

   this.render 'nav',
      to: 'nav'
      data: 'gallery'

   this.render 'gallery',
      to: 'content'
      data: myData

Router.route '/files', () ->

   this.render 'nav',
      to: 'nav'
      data: 'files'

   this.render 'fileTable',
      to: 'content'
      data: myData

Router.route '/jobs', () ->

   this.render 'nav',
      to: 'nav'
      data: 'jobs'

   this.render 'jobTable',
      to: 'content'
      data: myJobs

############################################################
# Client-only code
############################################################

if Meteor.isClient

   imageTypes =
      'image/jpeg': true
      'image/png': true
      'image/gif': true
      'image/tiff': true

   Meteor.startup () ->

      ################################
      # Setup resumable.js in the UI

      # Prevent default drop behavior (loading a file) outside of the drop zone
      window.addEventListener 'dragover', ((e) -> e.preventDefault()), false
      window.addEventListener 'drop', ((e) -> e.preventDefault()), false

      # When a file is added
      myData.resumable.on 'fileAdded', (file) ->
         if imageTypes[file.file.type]
            # Keep track of its progress reactivaly in a session variable
            Session.set file.uniqueIdentifier, 0
            # Create a new file in the file collection to upload to
            myData.insert({
                  _id: file.uniqueIdentifier    # This is the ID resumable will use
                  filename: file.fileName
                  contentType: file.file.type
               },
               (err, _id) ->
                  if err
                     console.warn "File creation failed!", err
                     return
                  # Once the file exists on the server, start uploading
                  myData.resumable.upload()
            )

      # Update the upload progress session variable
      myData.resumable.on 'fileProgress', (file) ->
         Session.set file.uniqueIdentifier, Math.floor(100*file.progress())

      # Finish the upload progress in the session variable
      myData.resumable.on 'fileSuccess', (file) ->
         Session.set file.uniqueIdentifier, undefined

      # More robust error handling needed!
      myData.resumable.on 'fileError', (file) ->
         console.warn "Error uploading", file.uniqueIdentifier
         Session.set file.uniqueIdentifier, undefined

   # Set up an autorun to keep the X-Auth-Token cookie up-to-date and
   # to update the subscription when the userId changes.
   Tracker.autorun () ->
      userId = Meteor.userId()
      Meteor.subscribe 'allData', userId
      Meteor.subscribe 'allJobs', userId
      $.cookie 'X-Auth-Token', Accounts._storedLoginToken()

   #####################
   # UI template helpers

   shorten = (name, w = 16) ->
      w++ if w % 2
      w = (w-2)/2
      if name.length > w
         name[0..w] + '...' + name[-w-1..-1]
      else
         name

   shortFilename = (w = 16) ->
      shorten this.filename, w

   isImage = () ->
      imageTypes[this.contentType]?

   Template.top.helpers
      loginToken: () ->
         Meteor.userId()
         Accounts._storedLoginToken()
      userId: () ->
         Meteor.userId()

   Template.nav.helpers
      active: (pill) ->
         return "active" if pill is "#{this}"

   Template.fileTable.helpers
      dataEntries: () ->
         # Reactively populate the table
         this.find({}, {sort:{filename: 1}})

      owner: () ->
         this.metadata?._auth?.owner

      id: () ->
         "#{this._id}"

      shortFilename: shortFilename

      uploadStatus: () ->
         percent = Session.get "#{this._id}"
         unless percent?
            "Processing..."
         else
            "Uploading..."

      formattedLength: () ->
         numeral(this.length).format('0.0b')

      uploadProgress: () ->
         percent = Session.get "#{this._id}"

      isImage: isImage

   Template.fileTable.events
      # Wire up the event to remove a file by clicking the `X`
      'click .del-file': (e, t) ->
         # Management of thumbnails happens on the server!
         if this.metadata.thumbOf?
            t.data.remove this.metadata.thumbOf
         else
            t.data.remove this._id

   Template.gallery.helpers
      dataEntries: () ->
         # Reactively populate the table
         this.find({'metadata.thumbOf': {$exists: false}}, {sort:{filename: 1}})

      id: () ->
         "#{this._id}"

      thumb: () ->
         "#{this.metadata.thumb}"

      isImage: isImage

      shortFilename: shortFilename

      altMessage: () ->
         if this.length isnt 0
            "Processing thumbnail..."
         else
            "Uploading..."

   Template.gallery.rendered = () ->
      # This assigns a file drop zone to the "file table"
      this.data.resumable.assignDrop $(".#{myData.root}DropZone")

   Template.fileControls.events
      'click .remove-files': (e, t) ->
         this.find({ 'metadata.thumbOf': {$exists: false} }).forEach ((d) -> this.remove(d._id)), this

   Template.jobTable.helpers
      jobEntries: () ->
         # Reactively populate the table
         this.find({})

   Template.jobEntry.rendered = () ->
      this.$('.button-column').tooltip({selector: 'button[data-toggle=tooltip]'})

   Template.jobEntry.events
      'click .cancel-job': (e, t) ->
         console.log "Cancelling job: #{this._id}", t
         job = Template.currentData()
         job.cancel() if job
      'click .remove-job': (e, t) ->
         console.log "Removing job: #{this._id}"
         job = Template.currentData()
         job.remove() if job
      'click .restart-job': (e, t) ->
         console.log "Restarting job: #{this._id}"
         job = Template.currentData()
         job.restart() if job
      'click .rerun-job': (e, t) ->
         console.log "Rerunning job: #{this._id}"
         job = Template.currentData()
         job.rerun({ wait: 15000 }) if job
      'click .pause-job': (e, t) ->
         console.log "Pausing job: #{this._id}"
         job = Template.currentData()
         job.pause() if job
      'click .resume-job': (e, t) ->
         console.log "Resuming job: #{this._id}"
         job = Template.currentData()
         job.resume() if job

   Template.jobEntry.helpers
      numDepends: () ->
         this.depends?.length

      numResolved: () ->
         this.resolved?.length

      jobId: () ->
         this._id.valueOf()

      statusBG: () ->
         {
            waiting: 'primary'
            ready: 'info'
            paused: 'default'
            running: 'default'
            cancelled: 'warning'
            failed: 'danger'
            completed: 'success'
         }[this.status]

      numRepeats: () ->
         if this.repeats is parent.Forever
            "∞"
         else
            this.repeats

      numRetries: () ->
         if this.retries is parent.Forever
            "∞"
         else
            this.retries

      runAt: () ->
         Session.get 'date'
         moment(this.after).fromNow()

      lastUpdated: () ->
         Session.get 'date'
         moment(this.updated).fromNow()

      futurePast: () ->
         Session.get 'date'
         if this.after > new Date()
            "text-danger"
         else
            "text-success"

      running: () ->
         if Template.instance().view.isRendered
            # This code destroys Bootstrap tooltips on existing buttons that may be
            # about to disappear. This is done here because by the time the template
            # autorun function runs, the button may already be out of the DOM, but
            # a "ghost" tooltip for that button can remain visible.
            Template.instance().$("button[data-toggle=tooltip]").tooltip('destroy')

         this.status is 'running'

      cancellable: () ->
         this.status in Template.parentData(2).jobStatusCancellable

      removable: () ->
         this.status in Template.parentData(2).jobStatusRemovable

      restartable: () ->
         this.status in Template.parentData(2).jobStatusRestartable

      rerunable: () ->
         this.status is 'completed'

      pausable: () ->
         this.status in Template.parentData(2).jobStatusPausable

      resumable: () ->
         this.status is 'paused'

   Template.jobControls.events
      'click .clear-completed': (e, t) ->
         console.log "clear completed"
         ids = t.data.find({ status: 'completed' },{ fields: { _id: 1 }}).map (d) -> d._id
         console.log "clearing: #{ids.length} jobs"
         t.data.removeJobs(ids) if ids.length > 0

      'click .pause-queue': (e, t) ->
         if $(e.target).hasClass 'active'
            console.log "resume queue"
            ids = t.data.find({ status: 'paused' },{ fields: { _id: 1 }}).map (d) -> d._id
            console.log "resuming: #{ids.length} jobs"
            t.data.resumeJobs(ids) if ids.length > 0
         else
            console.log "pause queue"
            ids = t.data.find({ status: { $in: t.data.jobStatusPausable }}, { fields: { _id: 1 }}).map (d) -> d._id
            console.log "pausing: #{ids.length} jobs"
            t.data.pauseJobs(ids) if ids.length > 0

      'click .stop-queue': (e, t) ->
         unless $(e.target).hasClass 'active'
            console.log "stop queue"
            t.data.stopJobs()
         else
            console.log "restart queue"
            t.data.stopJobs(0)

      'click .cancel-queue': (e, t) ->
         console.log "cancel all"
         ids = t.data.find({ status: { $in: t.data.jobStatusCancellable } }).map (d) -> d._id
         console.log "cancelling: #{ids.length} jobs"
         t.data.cancelJobs(ids) if ids.length > 0

      'click .restart-queue': (e, t) ->
         console.log "restart all"
         ids = t.data.find({ status: { $in: t.data.jobStatusRestartable } }).map (d) -> d._id
         console.log "restarting: #{ids.length} jobs"
         t.data.restartJobs(ids, (e, r) -> console.log("Restart returned", r)) if ids.length > 0

      'click .remove-queue': (e, t) ->
         console.log "remove all"
         ids = t.data.find({ status: { $in: t.data.jobStatusRemovable } }).map (d) -> d._id
         console.log "removing: #{ids.length} jobs"
         t.data.removeJobs(ids) if ids.length > 0

############################################################
# Server-only code
############################################################

if Meteor.isServer

   gm = Meteor.npmRequire 'gm'
   exec = Meteor.npmRequire('child_process').exec

   myJobs.setLogStream process.stdout
   myJobs.promote 2500

   Meteor.startup () ->

      myJobs.startJobServer()

      Meteor.publish 'allJobs', (clientUserId) ->
         # This prevents a race condition on the client between Meteor.userId() and subscriptions to this publish
         # See: https://stackoverflow.com/questions/24445404/how-to-prevent-a-client-reactive-race-between-meteor-userid-and-a-subscription/24460877#24460877
         if this.userId is clientUserId
            return myJobs.find({ 'data.owner': this.userId })
         else
            return []

      # Only publish files owned by this userId, and ignore temp file chunks used by resumable
      Meteor.publish 'allData', (clientUserId) ->
         # This prevents a race condition on the client between Meteor.userId() and subscriptions to this publish
         # See: https://stackoverflow.com/questions/24445404/how-to-prevent-a-client-reactive-race-between-meteor-userid-and-a-subscription/24460877#24460877
         if this.userId is clientUserId
            return myData.find({ 'metadata._Resumable': { $exists: false }, 'metadata._auth.owner': this.userId })
         else
            return []

      # Don't allow users to modify the user docs
      Meteor.users.deny({update: () -> true })

      # Only allow job owners to manage or rerun jobs
      myJobs.allow
         manager: (userId, method, params) ->
            ids = params[0]
            unless typeof ids is 'object' and ids instanceof Array
               ids = [ ids ]
            numIds = ids.length
            numMatches = myJobs.find({ _id: { $in: ids }, 'data.owner': userId }).count()
            return numMatches is numIds

         jobRerun: (userId, method, params) ->
            id = params[0]
            numMatches = myJobs.find({ _id: id, 'data.owner': userId }).count()
            return numMatches is 1

         stopJobs: (userId, method, params) ->
            return userId?

      # Allow rules for security. Without these, no writes would be allowed by default
      myData.allow
         insert: (userId, file) ->
            # Assign the proper owner when a file is created
            file.metadata = file.metadata ? {}
            file.metadata._auth =
               owner: userId
            true
         remove: (userId, file) ->
            # Only owners can delete
            if file.metadata?._auth?.owner and userId isnt file.metadata._auth.owner
               return false
            true
         read: (userId, file) ->
            # Only owners can GET file data
            if file.metadata?._auth?.owner and userId isnt file.metadata._auth.owner
               return false
            true
         write: (userId, file, fields) -> # This is for the HTTP REST interfaces PUT/POST
            # All client file metadata updates are denied, implement Methods for that...
            # Only owners can upload a file
            if file.metadata?._auth?.owner and userId isnt file.metadata._auth.owner
               return false
            true

      # Create a job to make a thumbnail for each newly uploaded image
      addedFileJob = (file) ->
         # Don't make new jobs for files tha already have them
         unless file?.metadata?._Job?
            outputFileId = myData.insert
               filename: "tn_#{file.filename}.png"
               contentType: 'image/png'
               metadata: file.metadata
            job = myJobs.createJob('makeThumb',
               owner: file.metadata._auth.owner
               inputFileURL: Meteor.absoluteUrl("#{myData.baseURL[1..]}/#{file._id}")
               outputFileURL: Meteor.absoluteUrl("#{myData.baseURL[1..]}/put/#{outputFileId}")
               inputFileId: file._id
               outputFileId: outputFileId
            )
            if jobId = job.delay(5000).retry({ wait: 20000, retries: 5 }).save()
               myData.update({ _id: file._id }, { $set: { 'metadata._Job': jobId }})
               myData.update({ _id: outputFileId }, { $set: { 'metadata._Job': jobId, 'metadata.thumbOf': file._id }})
            else
               console.error "Error saving new job for file #{file._id}"

      # If a removed file has an associated cancellable job, cancel it.
      removedFileJob = (file) ->
         if file.metadata?._Job
            if job = myJobs.findOne({_id: file.metadata._Job, status: { $in: myJobs.jobStatusCancellable }},{ fields: { log: 0 }})
               console.log "Cancelling the job for the removed file!", job._id
               job.cancel (err, res) ->
                  myData.remove
                     _id: job.data.outputFileId
         thumb = myData.remove { _id: file.metadata.thumb }

      # When a file's data changes, call the appropriate functions
      # for the removal of the old file and addition of the new.
      changedFileJob = (oldFile, newFile) ->
         if oldFile.md5 isnt newFile.md5
            if oldFile.metadata._Job?
               # Only call if this file has a job outstanding
               removedFileJob oldFile
            addedFileJob newFile

      # Watch for changes to uploaded image files
      fileObserve = myData.find(
         md5:
            $ne: 'd41d8cd98f00b204e9800998ecf8427e'  # md5 sum for zero length file
         'metadata._Resumable':
            $exists: false
         'metadata.thumbOf':
            $exists: false
      ).observe(
         added: addedFileJob
         changed: changedFileJob
         removed: removedFileJob
      )

      worker = (job, cb) ->
         exec 'gm version', Meteor.bindEnvironment (err) ->
            if err
               console.warn 'Graphicsmagick is not installed!\n', err
               job.fail "Error running graphicsmagick: #{err}", { fatal: true }
               return cb()

            outStream = myData.upsertStream { _id: job.data.outputFileId }, {}, (err, file) ->
               if err
                  job.fail "#{err}"
               else
                  job.progress 80, 100
                  myData.update { _id: job.data.inputFileId }, { $set: { 'metadata.thumb': job.data.outputFileId } }
                  job.done()
               cb()
            unless outStream
               job.fail 'Output file not found'
               cb null

            inStream = myData.findOneStream { _id: job.data.inputFileId }
            unless inStream
               outStream.releaseLock()
               job.fail 'Input file not found'
               cb null

            job.progress 20, 100

            gm(inStream)
               .resize(150,150)
               .stream('png')
               .pipe(outStream, (err) ->
                  console.warn 'Error running graphicsmagick:', err
                  outStream.releaseLock()
                  inStream.releaseLock()
                  job.fail "Error running graphicsmagick: #{err}"
                  cb()
               )

      workers = myJobs.processJobs 'makeThumb', { concurrency: 2, prefetch: 2, pollInterval: 1000000000 }, worker
      myJobs.find({ type: 'makeThumb', status: 'ready' })
             .observe
               added: (doc) ->
                  workers.trigger()
