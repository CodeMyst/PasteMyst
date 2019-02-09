module github;

import vibe.http.server : HTTPServerRequest;

void authorize ()
{
    import vibe.web.web : redirect;
    import appsettings : GitHubSettings, getGitHubSettings;

    auto settings = getGitHubSettings ();

    redirect ("https://github.com/login/oauth/authorize?client_id=" ~ settings.clientId ~ "&scope=read:user%20user:email");
}

string getAccessToken (string code)
{
    import vibe.http.client : requestHTTP;
    import vibe.http.common : HTTPMethod;
    import vibe.stream.operations : readAllUTF8;
    import vibe.data.json : parseJsonString;
    import appsettings : GitHubSettings, getGitHubSettings;

    auto settings = getGitHubSettings ();

    string accessToken;

    requestHTTP ("https://github.com/login/oauth/access_token?client_id=" ~ settings.clientId ~ "&client_secret=" ~ settings.clientSecret ~ "&code=" ~ code,
        (scope req)
        {
            req.method = HTTPMethod.POST;
            req.headers.addField ("Accept", "application/json");
        },
        (scope res)
        {
            accessToken = parseJsonString (res.bodyReader.readAllUTF8) ["access_token"].get!string;
        });

    return accessToken;
}

bool isLoggedIn (HTTPServerRequest req)
{
    return req.cookies.get ("github") !is null;
}

User getCurrentUser (HTTPServerRequest req)
{
    import vibe.http.client : requestHTTP;
    import vibe.data.json : parseJsonString, Json;
    import vibe.stream.operations : readAllUTF8;

    User user;

    string accessToken = req.cookies.get ("github");

    requestHTTP ("https://api.github.com/user",
        (scope req)
        {
            req.headers.addField ("Authorization", "token " ~ accessToken);
        },
        (scope res)
        {
            Json json = parseJsonString (res.bodyReader.readAllUTF8);
            user.name = json ["login"].get!string;
        });

    return user;
}

struct User
{
    string name;
}