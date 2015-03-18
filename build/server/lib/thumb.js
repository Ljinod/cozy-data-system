// Generated by CoffeeScript 1.9.1
var async, binaryManagement, createThumb, db, downloader, fs, gm, log, mime, queue, resize, whiteList,
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

fs = require('fs');

gm = require('gm');

mime = require('mime');

log = require('printit')({
  prefix: 'thumbnails'
});

db = require('../helpers/db_connect_helper').db_connect();

binaryManagement = require('../lib/binary');

downloader = require('./downloader');

async = require('async');

whiteList = ['image/jpeg', 'image/png'];

queue = async.queue(function(task, callback) {
  return createThumb(task.file, task.force, callback);
}, 2);

resize = function(srcPath, file, name, mimetype, force, callback) {
  var buildThumb, data, dstPath, err, gmRunner;
  if ((file.binary[name] != null) && !force) {
    return callback();
  }
  dstPath = "/tmp/" + name + "-" + file.name;
  data = {
    name: name,
    "content-type": mimetype
  };
  try {
    gmRunner = gm(srcPath).options({
      imageMagick: true
    });
    if (!fs.existsSync(srcPath)) {
      return callback("File doesn't exist");
    }
    try {
      fs.open(srcPath, 'r+', function(err, fd) {
        if (err) {
          return callback('Data-system has not correct permissions');
        }
        return fs.close(fd);
      });
    } catch (_error) {
      return callback('Data-system has not correct permissions');
    }
    if (name === 'thumb') {
      buildThumb = function(width, height) {
        return gmRunner.resize(width, height).crop(300, 300, 0, 0).write(dstPath, function(err) {
          var stream;
          if (err) {
            return callback(err);
          } else {
            stream = fs.createReadStream(dstPath);
            return binaryManagement.addBinary(file, data, stream, function(err) {
              if (err != null) {
                return callback(err);
              }
              return fs.unlink(dstPath, callback);
            });
          }
        });
      };
      return gmRunner.size(function(err, data) {
        if (err) {
          return callback(err);
        } else {
          if (data.width > data.height) {
            return buildThumb(null, 300);
          } else {
            return buildThumb(300, null);
          }
        }
      });
    } else if (name === 'screen') {
      return gmRunner.resize(1200, 800).write(dstPath, function(err) {
        var stream;
        if (err) {
          return callback(err);
        } else {
          stream = fs.createReadStream(dstPath);
          return binaryManagement.addBinary(file, data, stream, function(err) {
            if (err != null) {
              return callback(err);
            }
            return fs.unlink(dstPath, callback);
          });
        }
      });
    }
  } catch (_error) {
    err = _error;
    return callback(err);
  }
};

module.exports.create = function(file, force, callback) {
  return queue.push({
    file: file,
    force: force
  }, callback);
};

createThumb = function(file, force, callback) {
  var addThumb, id, mimetype, ref, ref1;
  addThumb = function(stream, mimetype) {
    var rawFile, writeStream;
    rawFile = "/tmp/" + file.name;
    try {
      writeStream = fs.createWriteStream(rawFile);
    } catch (_error) {
      return callback('Error in thumb creation.');
    }
    stream.pipe(writeStream);
    stream.on('error', callback);
    return stream.on('end', (function(_this) {
      return function() {
        return resize(rawFile, file, 'thumb', mimetype, force, function(err) {
          return resize(rawFile, file, 'screen', mimetype, force, function(err) {
            return fs.unlink(rawFile, function() {
              if (err) {
                log.error(err);
              } else {
                log.info("createThumb " + file.id + " /\n " + file.name + ": Thumbnail created");
              }
              return callback(err);
            });
          });
        });
      };
    })(this));
  };
  if (file.binary == null) {
    return callback(new Error('no binary'));
  }
  if ((((ref = file.binary) != null ? ref.thumb : void 0) != null) && (((ref1 = file.binary) != null ? ref1.screen : void 0) != null) && !force) {
    log.info("createThumb " + file.id + "/" + file.name + ": already created.");
    return callback();
  } else {
    mimetype = mime.lookup(file.name);
    if (indexOf.call(whiteList, mimetype) < 0) {
      log.info("createThumb: " + file.id + " / " + file.name + ": \nNo thumb to create for this kind of file.");
      return callback();
    } else {
      log.info("createThumb: " + file.id + " / " + file.name + ": Creation started...");
      id = file.binary['file'].id;
      return downloader.download(id, 'file', function(err, stream) {
        if (err) {
          return log.error(err);
        } else {
          return addThumb(stream, mimetype);
        }
      });
    }
  }
};
