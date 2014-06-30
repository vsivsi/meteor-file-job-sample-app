############################################################################
#     Copyright (C) 2014 by Vaughn Iverson
#     fileCollection is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

# Both client and server

# Default collection name is 'fs'
myData = FileCollection('images', {
   resumable: true,     # Enable the resumable.js compatible chunked file upload interface
   http: [
      { method: 'get', path: '/:_id', lookup: (params, query) -> return { _id: params._id }},
      { method: 'put', path: '/put/:_id', lookup: (params, query) -> return { _id: params._id }}
   ]}
   # Define a GET API that uses the md5 sum id files
)

myJobs = JobCollection 'queue'

############################################################
# Client-only code
############################################################

if Meteor.isClient

   imageTypes =
      'image/jpeg': true
      'image/png': true
      'image/gif': true
      'image/tiff': true

   Meteor.subscribe 'allJobs'

   Meteor.startup () ->

      ################################
      # Setup resumable.js in the UI

      # Prevent default drop behavior (loading a file) outside of the drop zone
      window.addEventListener 'dragover', ((e) -> e.preventDefault()), false
      window.addEventListener 'drop', ((e) -> e.preventDefault()), false

      # This assigns a file drop zone to the "file table"
      myData.resumable.assignDrop $(".#{myData.root}DropZone")

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
   Deps.autorun () ->
      userId = Meteor.userId()
      Meteor.subscribe 'allData', userId
      $.cookie 'X-Auth-Token', Accounts._storedLoginToken()

   #####################
   # UI template helpers

   Template.testApp.helpers
      loginToken: () ->
         Meteor.userId()
         Accounts._storedLoginToken()
      userId: () ->
         Meteor.userId()
      myData: () -> myData

   fileTableHelpers =
      dataEntries: () ->
         # Reactively populate the table
         this.find({})

      owner: () ->
         this.metadata?._auth?.owner

      id: () ->
         "#{this._id}"

      shortFilename: (w = 16) ->
         w++ if w % 2
         w = (w-2)/2
         if this.filename.length > w
            this.filename[0..w] + '...' + this.filename[-w-1..-1]
         else
            this.filename

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

      isImage: () ->
         types =
            'image/jpeg': true
            'image/png': true
            'image/gif': true
            'image/tiff': true
         types[this.contentType]?

   fileTableEvents =
      # Wire up the event to remove a file by clicking the `X`
      'click .del-file': (e, t) ->
         # Just the remove method does it all
         t.data.remove {_id: this._id}

   Template.gallery.helpers fileTableHelpers

   Template.fileTable.helpers fileTableHelpers
   Template.fileTable.events fileTableEvents

   Template.jobTable.events
      # Wire up the event to cancel a job by clicking the `X`
      'click .cancel-job': (e, t) ->
         console.log "Cancelling job: #{this._id}"
         job = myJobs.makeJob this
         job.cancel() if job
      'click .remove-job': (e, t) ->
         console.log "Removing job: #{this._id}"
         job = myJobs.makeJob this
         job.remove() if job
      'click .restart-job': (e, t) ->
         console.log "Restarting job: #{this._id}"
         job = myJobs.makeJob this
         job.restart() if job
      'click .rerun-job': (e, t) ->
         console.log "Rerunning job: #{this._id}"
         job = myJobs.makeJob this
         job.rerun({ wait: 15000 }) if job
      'click .pause-job': (e, t) ->
         console.log "Pausing job: #{this._id}"
         job = myJobs.makeJob this
         job.pause() if job
      'click .resume-job': (e, t) ->
         console.log "Resuming job: #{this._id}"
         job = myJobs.makeJob this
         job.resume() if job

   Template.jobTable.helpers
      jobEntries: () ->
         # Reactively populate the table
         myJobs.find({})

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
         if this.repeats > Math.pow 2, 31
            "∞"
         else
            this.repeats

      numRetries: () ->
         if this.retries > Math.pow 2, 31
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
         this.status is 'running'

      cancellable: () ->
         this.status in myJobs.jobStatusCancellable

      removable: () ->
         this.status in myJobs.jobStatusRemovable

      restartable: () ->
         this.status in myJobs.jobStatusRestartable

      rerunable: () ->
         this.status is 'completed'

      pausable: () ->
         this.status in myJobs.jobStatusPausable

      resumable: () ->
         this.status is 'paused'


   Template.jobControls.events

      'click .clear-completed': (e, t) ->
         console.log "clear completed"
         ids = []
         myJobs.find({ status: 'completed' },{ fields: { _id: 1 }}).forEach (d) -> ids.push d._id
         console.log "clearing: #{ids.length} jobs"
         myJobs.removeJobs(ids) if ids.length > 0

      'click .pause-queue': (e, t) ->
         ids = []
         if $(e.target).hasClass 'active'
            console.log "resume queue"
            myJobs.find({ status: 'paused' },{ fields: { _id: 1 }}).forEach (d) -> ids.push d._id
            console.log "resuming: #{ids.length} jobs"
            myJobs.resumeJobs(ids) if ids.length > 0
         else
            console.log "pause queue"
            myJobs.find({ status: { $in: myJobs.jobStatusPausable }}, { fields: { _id: 1 }}).forEach (d) -> ids.push d._id
            console.log "pausing: #{ids.length} jobs"
            myJobs.pauseJobs(ids) if ids.length > 0

      'click .stop-queue': (e, t) ->
         unless $(e.target).hasClass 'active'
            console.log "stop queue"
            myJobs.stopJobs()
         else
            console.log "restart queue"
            myJobs.stopJobs(0)

      'click .cancel-queue': (e, t) ->
         console.log "cancel all"
         ids = []
         myJobs.find({ status: { $in: myJobs.jobStatusCancellable } }).forEach (d) -> ids.push d._id
         console.log "cancelling: #{ids.length} jobs"
         myJobs.cancelJobs(ids) if ids.length > 0

      'click .restart-queue': (e, t) ->
         console.log "restart all"
         ids = []
         myJobs.find({ status: { $in: myJobs.jobStatusRestartable } }).forEach (d) -> ids.push d._id
         console.log "restarting: #{ids.length} jobs"
         myJobs.restartJobs(ids, (e, r) -> console.log("Restart returned", r)) if ids.length > 0

      'click .remove-queue': (e, t) ->
         console.log "remove all"
         ids = []
         myJobs.find({ status: { $in: myJobs.jobStatusRemovable } }).forEach (d) -> ids.push d._id
         console.log "removing: #{ids.length} jobs"
         myJobs.removeJobs(ids) if ids.length > 0

############################################################
# Server-only code
############################################################

if Meteor.isServer

   myJobs.setLogStream process.stdout
   myJobs.allow
      manager: (userId, method, params) -> return userId?
      jobRerun: (userId, method, params) -> return userId?

   Meteor.startup () ->

      myJobs.startJobs()

      Meteor.publish 'allJobs', () ->
         myJobs.find({})

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
         console.warn "Added file!", file
         # Don't make new jobs for files tha already have them
         unless file?.metadata?._Job?
            outputFileId = myData.insert
               filename: "tn_#{file.filename}.png"
               contentType: 'image/png'
               metadata: file.metadata
            job = myJobs.createJob('makeThumb',
               inputFileURL: Meteor.absoluteUrl("#{myData.baseURL[1..]}/#{file._id}")
               outputFileURL: Meteor.absoluteUrl("#{myData.baseURL[1..]}/put/#{outputFileId}")
               inputFileId: file._id
               outputFileId: outputFileId
            )
            if jobId = job.delay(5000).retry({ wait: 20000, retries: 10 }).save()
               myData.update({ _id: file._id }, { $set: { 'metadata._Job': jobId, 'metadata.thumb': outputFileId } })
               myData.update({ _id: outputFileId }, { $set: { 'metadata._Job': jobId, 'metadata.thumbOf': file._id } })
            else
               console.error "Error saving new job for file #{file._id}"

      # If a removed file has an associated cancellable job, cancel it.
      removedFileJob = (file) ->
         console.warn "Removed a file!", file._id
         if file.metadata?._Job
            if job = myJobs.findOne({_id: file.metadata._Job, status: { $in: myJobs.jobStatusCancellable }},{ fields: { log: 0 }})
               console.log "Cancelling the job for the removed file!", job._id
               myJobs.makeJob(job).cancel (err, res) ->
                  console.warn "Job cancelled!", job._id
                  myData.remove
                     _id: job.data.outputFileId
            else
               console.log "No cancellable job found!", file._id
         thumb = myData.remove { _id: file.metadata.thumb }

      # When a file's data changes, call the appropriate functions
      # for the removal of the old file and addition of the new.
      changedFileJob = (oldFile, newFile) ->
         console.warn "Changed file!", oldFile._id
         if oldFile.md5 isnt newFile.md5
            if oldFile.metadata._Job?
               # Only call if this file has a job outstanding
               console.warn 'Outstanding job!'
               removedFileJob oldFile
            addedFileJob newFile
         else
            console.warn "File data didn't change"

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
         job.prog ?= 0
         if job.prog < 100
            job.prog += 25
            console.log "In worker:", job.prog
            result = job.progress job.prog, 100
            if result and Math.random() > 0.25
               console.log "Job progress good, continuing job"
               job.log "Starting next phase: #{job.prog}"
               console.log "Job log good, continuing job"
               Meteor.setTimeout worker.bind(null, job, cb), 5000
            else
               console.warn "Job removed or shutting down, abort job!"
               job.fail("Job gone")
               cb null
         else
            job.done()
            cb null

      workers = myJobs.processJobs 'makeThumb', { concurrency: 2 }, worker

