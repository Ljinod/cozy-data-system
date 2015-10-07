// Generated by CoffeeScript 1.10.0
var S, cradle, db, fs, initLoginCouch, setup_credentials;

cradle = require('cradle');

S = require('string');

fs = require('fs');

initLoginCouch = function() {
  var data, err, error, lines;
  try {
    data = fs.readFileSync('/etc/cozy/couchdb.login');
  } catch (error) {
    err = error;
    console.log("No CouchDB credentials file found: /etc/cozy/couchdb.login");
    process.exit(1);
  }
  lines = S(data.toString('utf8')).lines();
  return lines;
};

setup_credentials = function() {
  var credentials, loginCouch;
  credentials = {
    host: process.env.COUCH_HOST || 'localhost',
    port: process.env.COUCH_PORT || '5984',
    cache: false,
    raw: false,
    db: process.env.DB_NAME || 'cozy'
  };
  if (process.env.NODE_ENV === 'production') {
    loginCouch = initLoginCouch();
    credentials.auth = {
      username: loginCouch[0],
      password: loginCouch[1]
    };
  }
  return credentials;
};

db = null;

exports.db_connect = function() {
  var connection, credentials;
  if (db == null) {
    credentials = setup_credentials();
    connection = new cradle.Connection(credentials);
    db = connection.database(credentials.db);
  }
  return db;
};
