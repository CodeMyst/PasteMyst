import { initEditors, addEditor, editors } from "../components/pastyEditor.js";

let savePressed = false;

window.addEventListener("load", async() =>
{
    initEditors();

    document.getElementsByClassName("add-editor")[0].addEventListener("click", addEditor);

    document.querySelector(".notice .save").addEventListener("click", () =>
    {
        for (let i = 0; i < editors.length; i++)
        {
            editors[i].titleInput.name = "title-" + i;

            let dropdownElements= editors[i].rootElement.querySelectorAll(".language-dropdown input[type=radio]");

            for (let d = 0; d < dropdownElements.length; d++)
            {
                dropdownElements[d].setAttribute("disabled", "");
            }

            let textarea = editors[i].rootElement.querySelector("textarea.editor");

            textarea.name = "code-" + i;
            textarea.textContent = editors[i].editor.getValue();
        }

        let langs = document.querySelectorAll("input[name=language]");

        for (let l = 0; l < langs.length; l++)
        {
            langs[l].setAttribute("name", "language-" + l);
            langs[l].value = editors[l].languageDropdown.value;
        }

        let ids = document.querySelectorAll("input[name=id]");

        for (let i = 0; i < ids.length; i++)
        {
            ids[i].setAttribute("name", "id-" + i);
        }

        let searches = document.querySelectorAll("input[name=search]");

        for (let i = 0; i < searches.length; i++)
        {
            searches[i].setAttribute("disabled", "");
        }

        savePressed = true;

        document.querySelector("form").submit();
    });

    window.addEventListener("beforeunload", (e) =>
    {
        if (checkChange() && !savePressed)
        {
            e.preventDefault();
            e.returnValue = "";
        }
    });
});

function checkChange()
{
    if (document.querySelector(`.paste-options input[name="title"]`).value !== "")
    {
        return true;
    }

    let tagsinput = document.querySelector(".paste-options input[name=tags]");

    if (tagsinput)
    {
        if (tagsinput.value !== "")
        {
            return true;
        }
    }

    for (let i = 0; i < editors.length; i++)
    {
        if (editors[i].titleInput.value !== "")
        {
            return true;
        }

        if (editors[i].editor.getValue() !== "")
        {
            return true;
        }
    }

    return false;
}
