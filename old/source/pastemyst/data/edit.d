module pastemyst.data.edit;

import vibe.data.serialization;
import pastemyst.data;
import std.typecons;

/++
 + holds information about a single paste edit
 +/
public struct Edit
{
    /++
     + unique id of the edit
     +/
    @name("_id")
    public string uniqueId;

    /++
     + edit id, multiple edits can share the same id to show that multiple properties were edited at the same time. this is an incrementing number
     +/
    public ulong editId;

    /++
     + type of edit
     +/
    public EditType editType;

    /++
     + various metadata, most used case is for storing which pasty was edited
     +/
    public string[] metadata;

    /++
     + actual edit, usually stores the old data
     +/
    public string edit;

    /++
     + unix time of when the edit was done
     +/
    public ulong editedAt;
}

/++
 + type of paste edit
 +/
public enum EditType
{
    title,
    pastyTitle,
    pastyLanguage,
    pastyContent,
    pastyAdded,
    pastyRemoved,
}

/++
 + returns the description of an edit type
 +/
public string editTypeDescription(Edit edit)
{
    final switch (edit.editType)
    {
        case EditType.title:
            return "title";
        case EditType.pastyTitle:
            return "title of pasty";
        case EditType.pastyLanguage:
            return "language of pasty";
        case EditType.pastyContent:
            return "contents of pasty";
        case EditType.pastyAdded:
            return "added pasty";
        case EditType.pastyRemoved:
            return "removed pasty";
    }
}

/++
 + returns the previous edit to the specified one
 + it checks for the proper types, and if current edit is the first one
 + assumes that the provided id is valid
 +/
public Edit getNextEdit(Paste paste, string editUniqueId)
{
    import std.algorithm : sort, countUntil;
    import std.array : array;

    Edit[] edits = sort!((a, b) => a.editId < b.editId)(paste.edits).array;

    ulong editIndex = edits.countUntil!((e) => e.uniqueId == editUniqueId);

    if (editIndex == -1)
    {
        return Edit.init;
    }

    const Edit edit = edits[editIndex];
    Edit tempEdit;
    editIndex++;

    while (true)
    {
        if (editIndex >= edits.length)
        {
            return Edit.init;
        }

        tempEdit = edits[editIndex];

        if (tempEdit.editId != edit.editId && tempEdit.editType == edit.editType && tempEdit.metadata == edit.metadata)
        {
            return tempEdit;
        }

        editIndex++;
    }
}

public Tuple!(string, "previous", string, "next") getNextTitle(Paste paste, Edit edit)
{
    const Edit nextEdit = getNextEdit(paste, edit.uniqueId);
    Tuple!(string, "previous", string, "next") res;
    res.previous = edit.edit;

    if (nextEdit == Edit.init)
    {
        res.next = paste.title;
    }
    else
    {
        res.next = nextEdit.edit;
    }

    if (res.next == "")
    {
        res.next = "(untitled)";
    }

    if (res.previous == "")
    {
        res.previous = "(untitled)";
    }

    return res;
}

public Tuple!(string, "previous", string, "next") getNextPastyTitle(Paste paste, Edit edit)
{
    import std.conv : to;
    import std.algorithm : countUntil;

    const Edit nextEdit = getNextEdit(paste, edit.uniqueId);
    Tuple!(string, "previous", string, "next") res;
    res.previous = edit.edit;

    ulong pastyIndex = paste.pasties.countUntil!((p) => p.id == edit.metadata[0]);

    if (nextEdit == Edit.init)
    {
        res.next = paste.pasties[pastyIndex].title;
    }
    else
    {
        res.next = nextEdit.edit;
    }

    if (res.next == "")
    {
        res.next = "(untitled)";
    }

    if (res.previous == "")
    {
        res.previous = "(untitled)";
    }

    return res;
}

public Tuple!(string, "previous", string, "next") getNextPastyLanguage(Paste paste, Edit edit)
{
    import std.conv : to;
    import std.algorithm : countUntil;

    const Edit nextEdit = getNextEdit(paste, edit.uniqueId);
    Tuple!(string, "previous", string, "next") res;
    res.previous = edit.edit;

    ulong pastyIndex = paste.pasties.countUntil!((p) => p.id == edit.metadata[0]);

    if (nextEdit == Edit.init)
    {
        res.next = paste.pasties[pastyIndex].language;
    }
    else
    {
        res.next = nextEdit.edit;
    }

    return res;
}

public string getPastyDiff(Edit edit)
{
    import std.array : split, join;
    import std.ascii : newline;

    // remove the first 2 lines of metadata
    return edit.edit.split(newline)[2..$].join(newline);
}

public Pasty getAddedPasty(Edit edit)
{
    Pasty res;

    res.id = edit.metadata[0];
    res.title = edit.metadata[1];
    res.language = edit.metadata[2];
    res.code = edit.edit;

    return res;
}

public Pasty getRemovedPasty(Edit edit)
{
    Pasty res;

    res.id = edit.metadata[0];
    res.title = edit.metadata[1];
    res.language = edit.metadata[2];
    res.code = edit.edit;

    return res;
}
