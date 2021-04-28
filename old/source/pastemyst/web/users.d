module pastemyst.web.users;

import vibe.d;
import pastemyst.data;
import pastemyst.auth;

/++
 + web interface for the /users endpoint
 +/
@path("/users")
public class UsersWeb
{
    @path("/:username")
    public void getUser(HTTPServerRequest req, string _username, string search = "")
    {
        import pastemyst.db : getAll, find, findOneById;
        import std.algorithm : canFind;
        import std.typecons : Nullable;
        import std.uni : toLower;

        auto userRes = getAll!User();

        Nullable!User userTemp;
        foreach (u; userRes)
        {
            if (u.username.toLower() == _username.toLower())
            {
                userTemp = u;
                break;
            }
        }

        if (userTemp.isNull())
        {
            throw new HTTPStatusException(HTTPStatus.notFound,
                    "user either not found or the profile isn't set to public.");
        }

        const user = userTemp.get();

        if (!user.publicProfile)
        {
            return;
        }

        const session = getSession(req);

        const title = user.username ~ " - public profile";

        auto res = find!BasePaste(
            [
                "ownerId": Bson(user.id),
                "isPublic": Bson(true),
            ]);

        BasePaste[] pastes;
        foreach (paste; res)
        {
            string pasteTitle;

            if (paste.encrypted)
            {
                pasteTitle = "(encrypted)";
            }
            else
            {
                pasteTitle = findOneById!Paste(paste.id).get().title;
            }

            if (search == "" || pasteTitle.toLower().canFind(search.toLower()))
            {
                pastes ~= paste;
            }
        }

        render!("publicProfile.dt", session, title, user, search, pastes);
    }
}
