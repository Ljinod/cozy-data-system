var client, db, dbHelper, encryption, feed, git, sharing;

git = require('git-rev');

db = require('../helpers/db_connect_helper').db_connect();

feed = require('../lib/feed');

dbHelper = require('../lib/db_remove_helper');

encryption = require('../lib/encryption');

client = require('../lib/indexer');

sharing = require('../lib/sharing');

module.exports.encryptPassword = function(req, res, next) {
  var error, password;
  try {
    password = encryption.encrypt(req.body.password);
  } catch (_error) {
    error = _error;
  }
  if (password != null) {
    req.body.password = password;
  }
  return next();
};

module.exports.decryptPassword = function(req, res, next) {
  var error, password;
  try {
    password = encryption.decrypt(req.doc.password);
  } catch (_error) {
    error = _error;
  }
  if (password != null) {
    req.doc.password = password;
  }
  return next();
};

module.exports.index = function(req, res) {
  return git.long(function(commit) {
    return git.branch(function(branch) {
      return git.tag(function(tag) {
        return res.send(200, "<strong>Cozy Data System</strong><br />\nrevision: " + commit + "  <br />\ntag: " + tag + " <br />\nbranch: " + branch + " <br />");
      });
    });
  });
};

module.exports.exist = function(req, res, next) {
  return db.head(req.params.id, function(err, response, status) {
    if (status === 200) {
      return res.send(200, {
        exist: true
      });
    } else if (status === 404) {
      return res.send(200, {
        exist: false
      });
    } else {
      return next(err);
    }
  });
};

module.exports.find = function(req, res) {
  delete req.doc._rev;

  /*sharing.selectDocPlug req.doc.id, (err, tuple) ->
      if err?
          console.log 'Plugdb select failed : ' + err
      else if tuple
          console.log 'select doc plugdb : ' + JSON.stringify tuple
      sharing.selectUserPlug req.doc.id, (err, tuple) ->
          if err?
              console.log 'Plugdb select failed : ' + err
          else if tuple
              console.log 'select user plugdb : ' + JSON.stringify tuple
   */
  return res.send(200, req.doc);
};

module.exports.create = function(req, res, next) {
  delete req.body._attachments;
  if (req.params.id != null) {
    return db.get(req.params.id, function(err, doc) {
      if (doc != null) {
        err = new Error("The document already exists.");
        err.status = 409;
        return next(err);
      } else {
        return db.save(req.params.id, req.body, function(err, doc) {
          if (err) {
            err = new Error("The document already exists.");
            err.status = 409;
            return next(err);
          } else {
            sharing.mapDocOnInsert(req.body, doc.id, function(err, mapIds) {
              if (err) {
                return console.log('Error on the mapping : ' + err);
              } else if ((mapIds != null) && mapIds.length > 0) {
                console.log("doc inserted, let's match now");
                return sharing.matchAfterInsert(mapIds, function(err, matchIds) {
                  if (err) {
                    return console.log('Error on the matching : ' + err);
                  }
                });
              }
            });
            return res.send(201, {
              _id: doc.id
            });
          }
        });
      }
    });
  } else {
    return db.save(req.body, function(err, doc) {
      if (err) {
        return next(err);
      } else {
        sharing.mapDocOnInsert(req.body, doc.id, function(err, mapIds) {
          if (err) {
            return console.log('Error on the mapping : ' + err);
          } else if ((mapIds != null) && mapIds.length > 0) {
            console.log("doc inserted, let's match now");
            return sharing.matchAfterInsert(mapIds, function(err, matchIds) {
              if (err) {
                return console.log('Error on the matching : ' + err);
              }
            });
          }
        });
        return res.send(201, {
          _id: doc.id
        });
      }
    });
  }
};

module.exports.update = function(req, res, next) {
  delete req.body._attachments;
  return db.save(req.params.id, req.body, function(err, response) {
    if (err) {
      return next(err);
    } else {
      res.send(200, {
        success: true
      });
      return next();
    }
  });
};

module.exports.upsert = function(req, res, next) {
  delete req.body._attachments;
  return db.get(req.params.id, function(err, doc) {
    return db.save(req.params.id, req.body, function(err, savedDoc) {
      if (err) {
        return next(err);
      } else if (doc != null) {
        res.send(200, {
          success: true
        });
        return next();
      } else {
        res.send(201, {
          _id: savedDoc.id
        });
        return next();
      }
    });
  });
};

module.exports["delete"] = function(req, res, next) {
  var id, send_success;
  id = req.params.id;
  send_success = function() {
    res.send(204, {
      success: true
    });
    return next();
  };
  return dbHelper.remove(req.doc, function(err, res) {
    if (err) {
      return next(err);
    } else {
      return client.del("index/" + id + "/", function(err, response, resbody) {
        return send_success();
      });
    }
  });
};

module.exports.merge = function(req, res, next) {
  delete req.body._attachments;
  return db.merge(req.params.id, req.body, function(err, doc) {
    if (err) {
      return next(err);
    } else {
      res.send(200, {
        success: true
      });
      return next();
    }
  });
};
