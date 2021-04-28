module pastemyst.db.db;

import vibe.d;
import std.typecons;
import pastemyst.data;

version(unittest)
{
    import dshould;
}

/++
 + List of all collections in the mongo db.
 +/
public const string[] collectionNames = ["pastes", "users", "api-keys", "sessions"];

private MongoDatabase mongo;

/++
 + Connects to the databases.
 +/
public void connect()
{
    import pastemyst.data : User, config;

    version(unittest)
    {
        connectMongo(config.mongoConnection, "pastemyst-test");
    }
    else
    {
        connectMongo(config.mongoConnection, "pastemyst");
    }

    mongo[getCollectionName!User].createIndex(["username": "text"]);
}

/++
 + Gets the proper collection name to use from a type.
 +/
private string getCollectionName(T)() @safe
{
    static if (is(T == Paste) || is(T == EncryptedPaste) || is(T == BasePaste))
    {
        return "pastes";
    }
    else static if (is(T == User))
    {
        return "users";
    }
    else static if (is(T == ApiKey))
    {
        return "api-keys";
    }
    else static if (is(T == pastemyst.auth.session.Session))
    {
        return "sessions";
    }
    else
    {
        static assert(false, "Cannot get collection name from type " ~ T.stringof);
    }
}

@("getting the collection name from a struct type")
unittest
{
    getCollectionName!Paste().should.equal("pastes");
}

private void connectMongo(string host, string dbName)
{
    mongo = connectMongoDB(host).getDatabase(dbName);
}

/++
 + Inserts an item into the Mongo DB.
 +
 + The collection is automatically determined from the item type. It will throw an error if you try to insert an invalid type.
 +/
public void insert(T)(T item)
{
    MongoCollection collection = mongo[getCollectionName!T()];

    collection.insert(serializeToJson(item));
}

/++
 + updates an item in the db
 +/
public void update(T, S, U)(S selector, U update)
{
    MongoCollection collection = mongo[getCollectionName!T()];

    collection.update(selector, update);
}

/++
 + Get the count of objects in the collection
 +/
public ulong getCollectionCount(T)()
{
    MongoCollection collection = mongo[getCollectionName!T()];

    return collection.find().count();
}

/++
 + returns all documents inside the specified collection
 +/
public MongoCursor!R getAll(R)() @safe
{
    MongoCollection collection = mongo[getCollectionName!R()];

    return collection.find!R();
}

/++
 + finds all elements in the specified collection that match the query
 +/
public MongoCursor!R find(R, T)(T query) @safe
{
    MongoCollection collection = mongo[getCollectionName!R()];

    return collection.find!R(query);
}

/++
 +
 + Gets one item from the Mongo DB.
 +
 + The collection is automatically determined from the item type. It will throw an error if you try to insert an invalid type.
 +/
public Nullable!R findOne(R, T)(T query) @safe
{
    MongoCollection collection = mongo[getCollectionName!R()];

    return collection.findOne!R(query);
}

/++
 +
 + Gets one item from the Mongo DB with the specified id (_id).
 +
 + The collection is automatically determined from the item type. It will throw an error if you try to insert an invalid type.
 +/
public Nullable!R findOneById(R, T)(T id) @safe
{
    return findOne!R(["_id": id]);
}

/++
 + gets one item from the mongo db with the specified id;
 +
 + tries to get the item, if it fails for any reason it returns null
 +/
public Nullable!R tryFindOneById(R, T)(T id) @safe
{
    try
    {
        return findOneById!R(id);
    }
    catch (Exception e)
    {
        return Nullable!R.init;
    }
}

/++
 + gets the number of unique edits of a paste
 +/
public ulong getNumberOfEdits(const Paste paste) @safe
{
    import std.array : array;
    import std.stdio : writeln;

    MongoCollection collection = mongo[getCollectionName!Paste()];

    return collection.distinct("edits.editId", ["_id": paste.id]).array.length;
}

/++
 + Removes items from the DB, using the specified query
 +/
public void remove(R, T)(T query) @safe
{
    MongoCollection collection = mongo[getCollectionName!R()];

    collection.remove(query);
}

/++
 + Removes an existing object, with the specified id
 +/
public void removeOneById(R, T)(T id) @safe
{
    remove!R(["_id": id]);
}
