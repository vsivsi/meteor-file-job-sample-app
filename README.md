## Meteor job-collection (+ file-collection) Sample App

If you are looking for just the basic Meteor file-collection sample app, it can now be found here: https://github.com/vsivsi/meteor-file-sample-app

This demo app uses [file-collection's](https://atmospherejs.com/vsivsi/file-collection) built-in support for [Resumable.js](http://www.resumablejs.com/) to allow drag and drop uploading of image files into a basic thumbnail gallery. It uses [job-collection](https://atmospherejs.com/vsivsi/job-collection) to automate creation of thumbnail images for each uploaded file. Besides the gallery view, the sample app also has "file" and "job" views observe and manage the underlying file and job collections directly and given examples for how basic UI controls for these packages can be implemented.

To set-up: just clone this repo, cd into its directory and run `meteor`, once it starts up point your browser at `http://localhost:3000/`.

You will also need to have [graphicsmagick](http://www.graphicsmagick.org/) installed on the server for use in making the image thumbnails. This may be easily installed on Mac OS X using MacPorts or Brew, and on Linux using your preferred package manager.
