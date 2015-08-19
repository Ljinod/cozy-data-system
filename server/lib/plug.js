var authFP, close, init, insertDoc, insertDocs, insertUser, java, jdbcJar, plug, selectDocs, selectSingleDoc, selectSingleUser, selectUsers;

java = require('java');

jdbcJar = './plug/plug_api.jar';

java.classpath.push(jdbcJar);

plug = java.newInstanceSync('org.cozy.plug.Plug');

init = function(callback) {
  var timeoutProtect;
  timeoutProtect = setTimeout((function() {
    timeoutProtect = null;
    return callback({
      error: 'PlugDB timed out'
    });
  }), 30000);
  return plug.plugInit('/dev/ttyACM0', function(err) {
    if (timeoutProtect) {
      clearTimeout(timeoutProtect);
      console.log('PlugDB ready');
      return callback(err);
    }
  });
};

insertDocs = function(ids, callback) {
  var array;
  array = java.newArray('java.lang.String', ids);
  plug.plugInsertDocs(array, function(err) {
    callback(err);
  });
};

insertDoc = function(docid, shareid, userParams, callback) {
  plug.plugInsertDoc(docid, shareid, userParams, function(err) {
    callback(err);
  });
};

insertUser = function(userid, shareid, userParams, callback) {
  plug.plugInsertDoc(docid, shareid, userParams, function(err) {
    callback(err);
  });
};

selectDocs = function(callback) {
  plug.plugSelectDocs(function(err, results) {
    callback(err, results);
  });
};

selectUsers = function(callback) {
  plug.plugSelectUsers(function(err, results) {
    callback(err, results);
  });
};

selectSingleDoc = function(docid, callback) {
  plug.plugSelectSingleDoc(docid, function(err, result) {
    callback(err, result);
  });
};

selectSingleUser = function(userid, callback) {
  plug.plugSelectSingleUser(userid, function(err, result) {
    callback(err, result);
  });
};

close = function(callback) {
  plug.plugClose(function(err) {
    callback(err);
  });
};

authFP = function(callback) {
  plug.plugFPAuthentication(function(err, authID) {
    callback(err, authID);
  });
};

exports.init = init;

exports.insertDocs = insertDocs;

exports.insertDoc = insertDoc;

exports.insertUser = insertUser;

exports.selectDocs = selectDocs;

exports.selectUsers = selectUsers;

exports.selectSingleDoc = selectSingleDoc;

exports.selectSingleUser = selectSingleUser;

exports.close = close;

exports.authFP = authFP;
