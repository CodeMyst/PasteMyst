module pastemyst.web.paste;

import vibe.d;
import vibe.web.auth;
import pastemyst.data;
import pastemyst.web;
import pastemyst.auth;
import pastemyst.db;
import pastemyst.paste;

import std.typecons : Nullable;
import std.variant;
import std.conv;
import std.path;
import std.algorithm;

/++
 + web interface for getting pastes
 +/
@requiresAuth
public class PasteWeb
{
    mixin Auth;

    private Variant getPaste(string id)
    {
        // Variant has to be declared
        Variant res;

        auto paste = tryFindOneById!Paste(id);

        if (!paste.isNull)
        {
            res = paste.get();
            return res;
        }

        auto encrypted = tryFindOneById!EncryptedPaste(id);

        if (!encrypted.isNull)
        {
            res = encrypted.get();
            return res;
        }

        res = null;
        return res;
    }

    private bool checkOwner(const BasePaste p, pastemyst.auth.Session s)
    {
        if (p.isPrivate) return p.ownerId == s.userId;
        else if (!p.isPrivate) return true;
        else return false;
    }

    private bool checkOwner(const Paste p, pastemyst.auth.Session s)
    {
        if (p.isPrivate) return p.ownerId == s.userId;
        else if (!p.isPrivate) return true;
        else return false;
    }

    private bool checkOwner(const EncryptedPaste p, pastemyst.auth.Session s)
    {
        if (p.isPrivate) return p.ownerId == s.userId;
        else if (!p.isPrivate) return true;
        else return false;
    }

    /++
     + GET /:id
     +
     + gets the paste with the specified id
     +/
    @path("/:id")
    @noAuth
    public void getPaste(string _id, HTTPServerRequest req)
    {
        const session = getSession(req);

        const res = getPaste(_id);

        // the result is a regular paste
        if (res.peek!Paste() !is null)
        {
            const paste = res.get!Paste();

            if (!checkOwner(paste, session)) return;

            const title = paste.title != "" ? paste.title : "(untitled)";

            render!("paste.dt", paste, title, session);
        }
        // the result is an encrypted paste
        else if (res.peek!EncryptedPaste() !is null)
        {
            const encryptedPaste = res.get!EncryptedPaste();

            if (!checkOwner(encryptedPaste, session)) return;

            const id = encryptedPaste.id;
            const title = "encrypted paste";

            render!("decrypt.dt", id, session, title);
        }
        // paste not found
        else
        {
            return;
        }
    }

    /++
     + GET /:id.zip
     +
     + downloads a paste as a zip file
     +/
    @path("/:id.zip")
    @noAuth
    public void getDownloadPaste(string _id, HTTPServerRequest req, HTTPServerResponse res)
    {
        if (!_id.endsWith(".zip")) return;

        // remove .zip form the id
        _id = _id[0..($-".zip".length)];

        const pasteRes = tryFindOneById!Paste(_id);

        if (pasteRes.isNull) return;

        const paste = pasteRes.get();

        if (paste.isPrivate) return;

        string path = createZip(paste);

        res.headers.addField!string(`Content-Disposition`, `attachment; filename="`~baseName(path)~`"`);
        sendFile(req, res, NativePath(path));
    }

    /++
     + POST /paste
     +
     + creates a paste
     +/
    @noAuth
    public void postPaste(string title, string tags, string expiresIn, bool isPrivate, bool isPublic,
            bool isAnonymous, bool encrypt, string password, string pasties, HTTPServerRequest req)
    {
        string ownerId = "";

        const session = getSession(req);

        if (session.loggedIn)
        {
            ownerId = session.userId;
        }

        Paste paste;
        EncryptedPaste encryptedPaste;

        if (!encrypt)
        {
            paste = createPaste(title, expiresIn, deserializeJson!(Pasty[])(pasties), isPrivate, ownerId);
        }
        else
        {
            encryptedPaste = createEncryptedPaste(title, expiresIn, deserializeJson!(Pasty[])(pasties),
                    isPrivate, ownerId, password);
        }

        if (isPublic)
        {
            enforceHTTP(session.loggedIn, HTTPStatus.forbidden,
                "you cant create a profile public paste if you are not logged in.");

            paste.isPublic = isPublic;
            encryptedPaste.isPublic = isPublic;
        }

        if (session.loggedIn)
        {
            if (isAnonymous)
            {
                enforceHTTP(!isPrivate && !isPublic,
                        HTTPStatus.badRequest,
                        "the paste cant be private or shown on the profile if its anonymous");

                paste.ownerId = "";
                encryptedPaste.ownerId = "";
            }

            if (isPrivate)
            {
                enforceHTTP(!isAnonymous && !isPublic, HTTPStatus.badRequest,
                    "the paste cant be anonymous or shown on the profile if its private");
            }
        }

        if (tags != "")
        {
            enforceHTTP(session.loggedIn, HTTPStatus.forbidden, "you cant tag pastes if you are not logged in.");
            paste.tags = tagsStringToArray(tags);
            encryptedPaste.tags = tagsStringToArray(tags);
        }

        if (!encrypt)
        {
            insert(paste);
            redirect("/" ~ paste.id);
        }
        else
        {
            insert(encryptedPaste);
            redirect("/" ~ encryptedPaste.id);
        }
    }

    /++
     + POST /:id/decrypt
     +
     + decrypts the paste
     +/
    @path("/:id")
    @noAuth
    public void postDecrypt(string _id, string password, HTTPServerRequest req)
    {
        import crypto.aes : AESUtils, AES256;
        import crypto.padding : PaddingMode;
        import scrypt.password : genScryptPasswordHash, SCRYPT_OUTPUTLEN_DEFAULT, SCRYPT_R_DEFAULT, SCRYPT_P_DEFAULT;

        const session = getSession(req);

        const res = tryFindOneById!EncryptedPaste(_id);

        enforceHTTP(!res.isNull, HTTPStatus.notFound, "paste not found or is not encrypted");

        const encryptedPaste = res.get();

        if (!checkOwner(encryptedPaste, session)) return;

        Paste paste;
        paste.id = encryptedPaste.id;
        paste.createdAt = encryptedPaste.createdAt;
        paste.expiresIn = encryptedPaste.expiresIn;
        paste.deletesAt = encryptedPaste.deletesAt;
        paste.ownerId = encryptedPaste.ownerId;
        paste.isPrivate = encryptedPaste.isPrivate;
        paste.isPublic = encryptedPaste.isPublic;
        paste.tags = encryptedPaste.tags.dup;
        paste.stars = encryptedPaste.stars;
        paste.encrypted = true;

        string passwordHash = genScryptPasswordHash(password, encryptedPaste.salt, SCRYPT_OUTPUTLEN_DEFAULT,
               524_288, SCRYPT_R_DEFAULT, SCRYPT_P_DEFAULT);

        string jsonData;

        try
        {
            ubyte[16] iv = 0;
            string key = cast(string) AESUtils.decrypt!AES256(cast(const(ubyte[])) encryptedPaste.encryptedKey,
                    passwordHash, iv, PaddingMode.PKCS5);

            jsonData = cast(string) AESUtils.decrypt!AES256(cast(const(ubyte[])) encryptedPaste.encryptedData,
                    key, iv, PaddingMode.PKCS5);
        }
        catch (Exception e)
        {
            redirect("/" ~ _id);
        }

        const data = deserializeJson!EncryptedPasteData(jsonData);

        paste.title = data.title;
        paste.pasties = data.pasties.dup;

        const title = paste.title != "" ? paste.title : "(untitled)";

        render!("paste.dt", paste, title, session);

        return;
    }

    /++
     + POST /:id/star
     +
     + stars the paste
     +/
    @path("/:id/star")
    @anyAuth
    public void postStar(string _id, HTTPServerRequest req)
    {
        const res = findOneById!BasePaste(_id);

        if (res.isNull)
        {
            return;
        }

        const paste = res.get();

        const session = getSession(req);

        if (!checkOwner(paste, session)) return;

        auto user = session.getSessionUser();

        int incAmnt = 1;

        // user already starred the paste, this will unstar
        if (user.stars.canFind(paste.id))
        {
            incAmnt = -1;
            user.stars = user.stars.remove(user.stars.countUntil(paste.id));
        }
        else
        {
            user.stars ~= paste.id;
        }

        update!User(["_id": user.id], ["$set": ["stars": user.stars]]);
        update!BasePaste(["_id": _id], ["$inc": ["stars": incAmnt]]);

        redirect("/" ~ _id);
    }

    /++
     + POST /:id/togglePrivate
     +
     + toggles whether the paste is private
     +/
    @path("/:id/togglePrivate")
    @noAuth
    public void postTogglePrivate(string _id, HTTPServerRequest req)
    {
        const session = getSession(req);

        enforceHTTP(session.loggedIn, HTTPStatus.forbidden);

        const res = getPaste(_id);

        if (res.peek!Paste() !is null)
        {
            const paste = res.get!Paste();

            if (paste.ownerId != "" && paste.ownerId == session.userId && !paste.isPublic)
            {
                update!Paste(["_id": _id], ["$set": ["isPrivate": !paste.isPrivate]]);
                redirect("/" ~ _id);
            }
        }
        else if (res.peek!EncryptedPaste() !is null)
        {
            const encPaste = res.get!EncryptedPaste();

            if (encPaste.ownerId != "" && encPaste.ownerId == session.userId && !encPaste.isPublic)
            {
                update!EncryptedPaste(["_id": _id], ["$set": ["isPrivate": !encPaste.isPrivate]]);
                redirect("/" ~ _id);
            }
        }
    }

    /++
     + POST /:id/togglePublicOnProfile
     +
     + toggles whether the paste is public on the user's profile
     +/
    @path("/:id/togglePublicOnProfile")
    @noAuth
    public void postTogglePublicOnProfile(string _id, HTTPServerRequest req)
    {
        const session = getSession(req);

        enforceHTTP(session.loggedIn, HTTPStatus.forbidden);

        const auto res = getPaste(_id);

        if (res.peek!Paste() !is null)
        {
            const paste = res.get!Paste();

            if (paste.ownerId != "" && paste.ownerId == session.userId && !paste.isPrivate)
            {
                update!Paste(["_id": _id], ["$set": ["isPublic": !paste.isPublic]]);
                redirect("/" ~ _id);
            }
        }
        else if (res.peek!EncryptedPaste() !is null)
        {
            const encPaste = res.get!EncryptedPaste();

            if (encPaste.ownerId != "" && encPaste.ownerId == session.userId && !encPaste.isPrivate)
            {
                update!Paste(["_id": _id], ["$set": ["isPublic": !encPaste.isPublic]]);
                redirect("/" ~ _id);
            }
        }
    }

    /++
     + POST /:id/anon
     +
     + makes the paste anonymous
     +/
    @path("/:id/anon")
    @noAuth
    public void postPasteAnon(string _id, HTTPServerRequest req)
    {
        const session = getSession(req);

        enforceHTTP(session.loggedIn, HTTPStatus.forbidden);

        auto res = getPaste(_id);

        if (res.peek!Paste() !is null)
        {
            auto paste = res.get!Paste();

            if (paste.ownerId != "" && paste.ownerId == session.userId)
            {
                paste.ownerId = "";
                paste.isPrivate = false;
                paste.isPublic = false;
                paste.tags.length = 0;
                paste.edits.length = 0;
                update!Paste(["_id": _id], paste);
                redirect("/" ~ _id);
            }
        }
        else if (res.peek!EncryptedPaste() !is null)
        {
            auto encPaste = res.get!EncryptedPaste();

            if (encPaste.ownerId != "" && encPaste.ownerId == session.userId)
            {
                encPaste.ownerId = "";
                encPaste.isPrivate = false;
                encPaste.isPublic = false;
                encPaste.tags.length = 0;
                update!EncryptedPaste(["_id": _id], encPaste);
                redirect("/" ~ _id);
            }
        }
    }

    /++
     + POST /:id/delete
     +
     + deletes a user's paste
     +/
    @path("/:id/delete")
    @noAuth
    public void postPasteDelete(string _id, HTTPServerRequest req)
    {
        const session = getSession(req);

        enforceHTTP(session.loggedIn, HTTPStatus.forbidden);

        const res = getPaste(_id);

        if (res.peek!Paste() !is null)
        {
            const paste = res.get!Paste();

            if (paste.ownerId != "" && paste.ownerId == session.userId)
            {
                removeOneById!Paste(_id);
                redirect("/user/profile");
            }
        }
        else if (res.peek!EncryptedPaste() !is null)
        {
            const encPaste = res.get!EncryptedPaste();

            if (encPaste.ownerId != "" && encPaste.ownerId == session.userId)
            {
                removeOneById!EncryptedPaste(_id);
                redirect("/user/profile");
            }
        }
    }

    @path("/raw/:pasteId/:pastyId")
    @noAuth
    public void getRawPasty(string _pasteId, string _pastyId)
    {
        getRawPasty(_pasteId, _pastyId, -1);
    }

    /++
     + GET /raw/:id/index
     +
     + gets the raw data of the pasty
     +/
    @path("/raw/:pasteId/:pastyId/:editId")
    @noAuth
    public void getRawPasty(string _pasteId, string _pastyId, long _editId)
    {
        const auto res = tryFindOneById!Paste(_pasteId);

        if (res.isNull())
        {
            return;
        }

        if (res.get().isPrivate)
        {
            return;
        }

        if (_editId < -1)
        {
            return;
        }

        auto paste = pasteRevision(_pasteId, _editId);

        if (!paste.pasties.canFind!((p) => p.id == _pastyId))
        {
            return;
        }

        const Pasty pasty = paste.pasties.find!((p) => p.id == _pastyId)[0];

        const string pasteTitle = paste.title == "" ? "untitled" : paste.title;
        const string pastyTitle = pasty.title == "" ? "untitled" : pasty.title;
        const string title = pasteTitle ~ " - " ~ pastyTitle;
        const string rawCode = pasty.code;

        render!("raw.dt", title, rawCode);
    }

    /++
     + GET /:id/edit
     +
     + page for editing the paste
     +/
    @path("/:id/edit")
    @anyAuth
    public void getPasteEdit(string _id, HTTPServerRequest req)
    {
        const session = getSession(req);
        auto res = tryFindOneById!Paste(_id);

        if (res.isNull())
        {
            return;
        }

        const paste = res.get();

        if (paste.ownerId != session.userId)
        {
            return;
        }

        render!("editPaste.dt", session, paste);
    }

    /++
     + POST /:id/edit
     +
     + edit a paste
     +/
    @path("/:id/edit")
    @method(HTTPMethod.POST)
    @anyAuth
    public void postPasteEdit(string _id, HTTPServerRequest req)
    {
        import std.array : split, join;
        import std.datetime : Clock;
        import pastemyst.util : generateDiff, generateUniqueEditId, generateUniquePastyId;

        auto res = tryFindOneById!Paste(_id);

        if (res.isNull())
        {
            return;
        }

        const session = getSession(req);

        Paste paste = res.get();

        if (paste.ownerId != session.userId)
        {
            return;
        }

        Paste editedPaste;
        editedPaste.title = req.form["title"];

        string tagsString = req.form["tags"];
        editedPaste.tags = tagsStringToArray(tagsString);

        int i = 0;
        while(true)
        {
            Pasty pasty;
            if (("title-" ~ i.to!string()) !in req.form)
            {
                break;
            }

            pasty.id = req.form["id-" ~ i.to!string()];
            pasty.title = req.form["title-" ~ i.to!string()];
            pasty.language = req.form["language-" ~ i.to!string()].split(",")[0];
            pasty.code = req.form["code-" ~ i.to!string()];
            editedPaste.pasties ~= pasty;

            i++;
        }

        ulong editId = 0;
        if (paste.edits.length > 0)
        {
            editId = paste.edits[$-1].editId + 1;
        }
        const editedAt = Clock.currTime().toUnixTime();

        if (paste.title != editedPaste.title)
        {
            Edit edit;
            edit.uniqueId = generateUniqueEditId(paste);
            edit.editId = editId;
            edit.editType = EditType.title;
            edit.edit = paste.title;
            edit.editedAt = editedAt;

            paste.title = editedPaste.title;
            paste.edits ~= edit;
        }

        if (paste.tags != editedPaste.tags)
        {
            paste.tags = editedPaste.tags;
        }

        foreach (editedPasty; editedPaste.pasties)
        {
            if (paste.pasties.canFind!((p) => p.id == editedPasty.id))
            {
                ulong pastyIndex = paste.pasties.countUntil!((p) => p.id == editedPasty.id);
                Pasty pasty = paste.pasties[pastyIndex];

                if (pasty.title != editedPasty.title)
                {
                    Edit edit;
                    edit.uniqueId = generateUniqueEditId(paste);
                    edit.editId = editId;
                    edit.editType = EditType.pastyTitle;
                    edit.edit = pasty.title;
                    edit.metadata ~= pasty.id.to!string();
                    edit.editedAt = editedAt;

                    pasty.title = editedPasty.title;
                    paste.pasties[pastyIndex] = pasty;
                    paste.edits ~= edit;
                }

                if (pasty.language != editedPasty.language)
                {
                    enforceHTTP(editedPasty.language.toLower() != "auotedect",
                                HTTPStatus.badRequest,
                                "can't edit a pasty to have an autodetect language.");

                    pasty.language = getLanguageName(pasty.language);
                    enforceHTTP(!(pasty.language is null), HTTPStatus.badRequest, "invalid language value.");

                    Edit edit;
                    edit.uniqueId = generateUniqueEditId(paste);
                    edit.editId = editId;
                    edit.editType = EditType.pastyLanguage;
                    edit.edit = pasty.language;
                    edit.metadata ~= pasty.id.to!string();
                    edit.editedAt = editedAt;

                    pasty.language = editedPasty.language;
                    paste.pasties[pastyIndex] = pasty;
                    paste.edits ~= edit;
                }

                if (pasty.code != editedPasty.code)
                {
                    Edit edit;
                    edit.uniqueId = generateUniqueEditId(paste);
                    edit.editId = editId;
                    edit.editType = EditType.pastyContent;
                    edit.metadata ~= pasty.id.to!string();
                    edit.editedAt = editedAt;

                    string diffId = paste.id ~ "-" ~ edit.uniqueId;

                    edit.edit = generateDiff(diffId, pasty.code, editedPasty.code);

                    pasty.code = editedPasty.code;
                    paste.pasties[pastyIndex] = pasty;
                    paste.edits ~= edit;
                }
            }
        }

        foreach (pasty; paste.pasties)
        {
            if (!editedPaste.pasties.canFind!((p) => p.id == pasty.id))
            {
                Edit edit;
                edit.uniqueId = generateUniqueEditId(paste);
                edit.editId = editId;
                edit.editType = EditType.pastyRemoved;
                edit.edit = pasty.code;
                edit.metadata ~= pasty.id;
                edit.metadata ~= pasty.title;
                edit.metadata ~= pasty.language;
                edit.editedAt = editedAt;

                paste.pasties = paste.pasties.remove!((p) => p.id == pasty.id);
                paste.edits ~= edit;
            }
        }

        foreach (editedPasty; editedPaste.pasties)
        {
            if (editedPasty.id == "")
            {
                Edit edit;
                edit.uniqueId = generateUniqueEditId(paste);
                edit.editId = editId;
                edit.editType = EditType.pastyAdded;
                edit.edit = editedPasty.code;
                edit.editedAt = editedAt;

                editedPasty.id = generateUniquePastyId(paste);
                paste.pasties ~= editedPasty;

                edit.metadata ~= editedPasty.id;
                edit.metadata ~= editedPasty.title;
                edit.metadata ~= editedPasty.language;

                paste.edits ~= edit;
            }
        }

        update!Paste(["_id": _id], paste);

        redirect("/" ~ _id);
    }

    /++
     + GET /:id/history
     +
     + get all the edits of a paste
     +/
    @path("/:id/history")
    @noAuth
    public void getPasteHistory(string _id, HTTPServerRequest req)
    {
        auto res = tryFindOneById!Paste(_id);

        if (res.isNull())
        {
            return;
        }

        Paste paste = res.get();
        // this line is here because otherwise d-scanner
        // complains that paste isn't changed anywhere and it can be
        // declared const
        paste.title = paste.title;

        const session = getSession(req);

        if (!checkOwner(paste, session)) return;

        render!("history.dt", session, paste);
    }

    /++
     + GET /:pasteId/history/:editId
     +
     + gets the paste at the specific edit
     +/
    @path("/:pasteId/history/:editId")
    @noAuth
    public void getPasteRevision(string _pasteId, ulong _editId, HTTPServerRequest req)
    {
        const Paste paste = pasteRevision(_pasteId, _editId);

        if (paste == Paste.init)
        {
            return;
        }

        const session = getSession(req);

        if (paste.isPrivate && paste.ownerId != session.userId)
        {
            return;
        }

        const bool previousRevision = true;
        const ulong currentEditId = _editId;
        render!("paste.dt", session, paste, previousRevision, currentEditId);
    }

    @path("/:id/embed")
    @noAuth
    public void getPasteEmbed(string _id)
    {
        auto res = tryFindOneById!Paste(_id);

        if (res.isNull || res.get().isPrivate)
        {
            render!("embed.dt");
            return;
        }

        const paste = res.get();

        render!("embed.dt", paste);
    }

    private Paste pasteRevision(string _pasteId, ulong _editId)
    {
        import pastemyst.util : patchDiff;

        auto res = tryFindOneById!Paste(_pasteId);

        if (res.isNull)
        {
            return Paste.init;
        }

        Paste paste = res.get();

        // -1 is the latest paste
        if (_editId == -1)
        {
            return paste;
        }

        // if there are no edits, and the user is looking for the first edit
        // redirect to the current version
        if (_editId == 0 && paste.edits.length == 0)
        {
            return paste;
        }
        // check if the edit id is greater then the length of edits by one
        // this means the user is looking for the current version
        // this allows getting a permlink to the current version, even if more edits
        // will be made in the future
        else if (_editId > 0 && _editId == paste.edits.length)
        {
            return paste;
        }

        // check if edit id is invalid
        if (_editId > 0 && _editId > paste.edits.length)
        {
            return Paste.init;
        }

        foreach (edit; paste.edits.reverse())
        {
            final switch (edit.editType)
            {
                case EditType.title:
                {
                    paste.title = edit.edit;
                } break;

                case EditType.pastyTitle:
                {
                    ulong pastyIndex = paste.pasties.countUntil!((p) => p.id == edit.metadata[0]);
                    paste.pasties[pastyIndex].title = edit.edit;
                } break;

                case EditType.pastyLanguage:
                {
                    ulong pastyIndex = paste.pasties.countUntil!((p) => p.id == edit.metadata[0]);
                    paste.pasties[pastyIndex].language = edit.edit;
                } break;

                case EditType.pastyContent:
                {
                    ulong pastyIndex = paste.pasties.countUntil!((p) => p.id == edit.metadata[0]);
                    string diffId = _pasteId ~ "-" ~ edit.uniqueId;
                    paste.pasties[pastyIndex].code = patchDiff(diffId, paste.pasties[pastyIndex].code, edit.edit);
                } break;

                case EditType.pastyAdded:
                {
                    paste.pasties = paste.pasties.remove!((p) => p.id == edit.metadata[0]);
                } break;

                case EditType.pastyRemoved:
                {
                    // TODO: this adds to the end of the list, while the paste might've been
                    // removed from the middle of the list
                    Pasty p;
                    p.id = edit.metadata[0];
                    p.title = edit.metadata[1];
                    p.language = edit.metadata[2];
                    p.code = edit.edit;
                    paste.pasties ~= p;
                } break;
            }

            if (edit.editId == _editId)
            {
                break;
            }
        }

        return paste;
    }
}
