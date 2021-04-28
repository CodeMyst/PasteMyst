import { timeDifferenceToString } from "../helpers/time.js";
import { getWordwrap, getTheme } from "../helpers/options.js";

let highlightExpr = /(\d)L(\d+)(?:-L(\d+))?/;
let editors = [];
let highlightedLines = [];

let langCache = new Map();

window.addEventListener("load", async () =>
{
    let textareas = document.querySelectorAll("textarea");

    for (let i = 0; i < textareas.length; i++)
    {
        let editor = CodeMirror.fromTextArea(textareas[i], // jshint ignore:line
        {
            indentUnit: 4,
            lineNumbers: true,
            mode: "text/plain",
            tabSize: 4,
            theme: getTheme(),
            lineWrapping: getWordwrap(),
            readOnly: true,
            extraKeys:
            {
                Tab: (cm) => cm.execCommand("insertSoftTab")
            }
        });

        if (textareas[i].classList.length > 0)
        {
            editor.getWrapperElement().classList.add(textareas[i].classList);
        }

        let langMime = await loadLanguage(langs[i]); // jshint ignore:line
        let langColor;

        editor.setOption("mode", langMime);

        langColor = langCache.get(langs[i])[1]; // jshint ignore:line

        if (langColor)
        {
            let langTextElem = textareas[i].closest(".pasty").getElementsByClassName("lang")[0];

            langTextElem.style.backgroundColor = langColor;

            if (getColor(langColor))
            {
                langTextElem.style.color = "white";
            }
            else
            {
                langTextElem.style.color = "black";
            }
        }

        editors.push(editor);
    }

    let createdAtDate = new Date(createdAt * 1000); // jshint ignore:line

    document.querySelector(".paste-meta .created-at .value").textContent = " " + createdAtDate.toString().toLowerCase();

    if (deletesAt !== 0) // jshint ignore:line
    {
        let expiresIn = timeDifferenceToString(deletesAt * 1000 - new Date()); // jshint ignore:line
        document.querySelector(".paste-meta .expires-in .value").textContent = " " + expiresIn;
    }

    let editedAtDate = new Date(editedAt * 1000); // jshint ignore:line

    if (editedAt !== 0) // jshint ignore:line
    {
        document.querySelector(".paste-meta .edited-at .value").textContent = " " + editedAtDate.toString().toLowerCase();
    }

    let copyButtons = document.querySelectorAll("#paste .paste-pasties .pasty .pasty-header .copy");

    for (let i = 0; i < copyButtons.length; i++)
    {
        copyButtons[i].addEventListener("click", () => copyCodeToClipboard(copyButtons[i])); // jshint ignore:line
    }

    let copyLinkButton = document.querySelector("#paste .paste-header .copy-link");
    let copyLink = copyLinkButton.getAttribute("href");
    copyLinkButton.addEventListener("click", () => copyLinkToClipboard(copyLinkButton, copyLink));
    copyLinkButton.removeAttribute("href");

    let copyLinkEditButton = document.querySelector("#paste .paste-header .copy-link-edit");
    let copyEditLink = copyLinkEditButton.getAttribute("href");
    copyLinkEditButton.addEventListener("click", () => copyLinkToClipboard(copyLinkEditButton, copyEditLink));
    copyLinkEditButton.removeAttribute("href");

    const embedScriptCopy = document.querySelector(".embed-script-copy");
    const embedScript = document.querySelector(".embed-script");
    if (embedScriptCopy)
    {
        embedScriptCopy.addEventListener("click", () =>
        {
            copyToClipboard(embedScript.value);
            let textElem = embedScriptCopy.querySelector(".tooltip-text");
            let originalText = textElem.textContent;
            textElem.textContent = "copied";
            setTimeout(function(){ textElem.textContent = originalText; }, 2000);
        });
    }

    // hacky solution for a problem
    // sometimes on hard refresh the selected text in the editor was offset
    // needs a timeout because some unknown css file that causes this issue was getting loaded
    // after the editors
    setTimeout(function(){
        for (let i = 0; i < editors.length; i++) {
            editors[i].refresh();

            let lines = editors[i].getWrapperElement().getElementsByClassName("CodeMirror-linenumber");

            let start;
            let end;

            for (let j = 0; j < lines.length; j++)
            {
                lines[j].addEventListener("click", (e) => // jshint ignore:line
                {
                    if (!e.shiftKey)
                    {
                        // start marker
                        start = j+1;
                        end = undefined;
                    }
                    else
                    {
                        // end marker
                        if (start === undefined)
                        {
                            start = j+1;
                        }
                        else
                        {
                            if ((j+1) < start)
                            {
                                end = start;
                                start = j+1;
                            }
                            else
                            {
                                end = j+1;
                            }
                        }
                    }

                    if (end !== undefined)
                    {
                        location.hash = i + "L" + start + "-L" + end;
                    }
                    else
                    {
                        location.hash = i + "L" + start;
                    }

                    highlightLines();
                });
            }
        }

        highlightLines();
        jumpToHighlight();
    }, 100);
});

function copyCodeToClipboard(copyButton)
{
    let textarea = copyButton.closest(".pasty").querySelector("textarea");

    let originalText = copyButton.textContent;

    copyToClipboard(textarea.textContent);

    copyButton.textContent = "copied";

    setTimeout(function(){ copyButton.textContent = originalText; }, 2000);
}

function copyLinkToClipboard(button, link)
{
    let url = window.location.protocol + "//" + window.location.host + link;

    copyToClipboard(url);

    let textElem = button.querySelector(".tooltip-text");

    let originalText = textElem.textContent;

    textElem.textContent = "copied";

    setTimeout(function(){ textElem.textContent = originalText; }, 2000);
}

async function loadLanguage(lang)
{
    if (lang === "HTML")
    {
        await loadLanguage("XML");
    }

    if (lang === "JSX")
    {
        await loadLanguage("XML");
        await loadLanguage("JavaScript");
    }

    let langMime;

    if (langCache.has(lang)) // jshint ignore:line
    {
        langMime = langCache.get(lang)[0]; // jshint ignore:line
    }
    else
    {
        let res = await fetch(`/api/v2/data/language?name=${encodeURIComponent(lang)}`, // jshint ignore:line
        {
            headers:
            {
                "Content-Type": "application/json"
            }
        });

        let langData = await res.json();

        if (langData.mode && langData.mode !== "null")
        {
            await import(`../libs/codemirror/${langData.mode}/${langData.mode}.js`).then(() => // jshint ignore:line
            {
                langMime = langData.mimes[0];
                langCache.set(lang, [langData.mimes[0], langData.color]); // jshint ignore:line
            });
        }
        else
        {
            langMime = "text/plain";
            langCache.set(lang, ["text/plain", "#ffffff"]); // jshint ignore:line
        }
    }

    return langMime;
}

const copyToClipboard = str => {
  const el = document.createElement('textarea');  // Create a <textarea> element
  el.value = str;                                 // Set its value to the string that you want copied
  el.setAttribute('readonly', '');                // Make it readonly to be tamper-proof
  el.style.position = 'absolute';                 
  el.style.left = '-9999px';                      // Move outside the screen to make it invisible
  document.body.appendChild(el);                  // Append the <textarea> element to the HTML document
  const selected =            
    document.getSelection().rangeCount > 0 ? document.getSelection().getRangeAt(0) : false;                                    // Mark as false to know no selection existed before
  el.select();                                    // Select the <textarea> content
  document.execCommand('copy');                   // Copy - only works as a result of a user action (e.g. click events)
  document.body.removeChild(el);                  // Remove the <textarea> element
  if (selected) {                                 // If a selection existed before copying
    document.getSelection().removeAllRanges();    // Unselect everything on the HTML document
    document.getSelection().addRange(selected);   // Restore the original selection
  }
};

function highlightLines()
{
    for (let i = 0; i < highlightedLines.length; i++)
    {
        highlightedLines[i].classList.remove("line-highlight");
    }

    highlightedLines = [];

    let res = location.hash.match(highlightExpr);

    if (res === null)
    {
        return;
    }
    else if (res[1] !== undefined)
    {
        // select the pasty
        let editor = editors[res[1]];
        
        if (res[3] === undefined)
        {
            // single line highlight
            let line = res[2];

            highlightLine(editor, line);
        }
        else
        {
            let startLine = res[2];
            let endLine = res[3];

            for (let i = parseInt(startLine); i <= parseInt(endLine); i++)
            {
                highlightLine(editor, i);
            }
        }
    }
}

function highlightLine(editor, lineNum)
{
    let lineNumElem = editor.getWrapperElement().getElementsByClassName("CodeMirror-linenumber")[lineNum-1];
    let lineElem = lineNumElem.parentElement.parentElement;
    lineElem.classList.add("line-highlight");
    highlightedLines.push(lineElem);
}

function jumpToHighlight()
{
    if (highlightedLines.length === 0)
    {
        return;
    }

    const yOffset = -50; 
    const element = highlightedLines[0];
    const y = element.getBoundingClientRect().top + window.pageYOffset + yOffset;

    window.scrollTo({top: y});
}

/**
 * Figures out whether to use a white or black text colour based on the background colour.
 * The colour should be in a #RRGGBB format, # is needed!
 * Returns true if the text should be white.
 */
function getColor(bgColor)
{
    let red = parseInt(bgColor.substring(1, 3), 16);
    let green = parseInt(bgColor.substring(3, 5), 16);
    let blue = parseInt(bgColor.substring(5, 7), 16);

    return (red * 0.299 + green * 0.587 + blue * 0.114) <= 186;
}
