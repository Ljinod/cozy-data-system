// Generated by CoffeeScript 1.9.1
var binaryManagement, db, downloader, fs, gm, log, mime, thumb, whiteList,
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

whiteList = ['image/jpeg', 'image/png'];

module.exports = thumb = {
  resize: function(srcPath, file, name, mimetype, callback) {
    var buildThumb, data, dstPath, err, gmRunner;
    dstPath = "/tmp/thumb-" + file.name;
    data = {
      name: name,
      "content-type": mimetype
    };
    try {
      gmRunner = gm(srcPath).options({
        imageMagick: true
      });
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
  },
  create: function(file, callback) {
    var id, mimetype, rawFile, ref, request;
    if (file.binary == null) {
      return callback(new Error('no binary'));
    }
    if (((ref = file.binary) != null ? ref.thumb : void 0) != null) {
      log.info("createThumb " + file.id + "/" + file.name + ": already created.");
      return callback();
    } else {
      mimetype = mime.lookup(file.name);
      if (indexOf.call(whiteList, mimetype) < 0) {
        log.info("createThumb: " + file.id + " / " + file.name + ": \nNo thumb to create for this kind of file.");
        return callback();
      } else {
        log.info("createThumb: " + file.id + " / " + file.name + ": Creation started...");
        rawFile = "/tmp/" + file.name;
        id = file.binary['file'].id;
        return request = downloader.download(id, 'file', function(err, stream) {
          if (err) {
            return log.error(err);
          } else {
            stream.pipe(fs.createWriteStream(rawFile));
            stream.on('error', callback);
            return stream.on('end', (function(_this) {
              return function() {
                return thumb.resize(rawFile, file, 'thumb', mimetype, function(err) {
                  return fs.unlink(rawFile, function() {
                    if (err) {
                      log.error(err);
                    } else {
                      log.info("createThumb " + file.id + " /\n " + file.name + ": Thumbnail created");
                    }
                    return callback(err);
                  });
                });
              };
            })(this));
          }
        });
      }
    }
  }
};
