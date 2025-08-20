document.addEventListener("DOMContentLoaded", function () {
  // Select all pre.highlight elements, which wrap your syntax-highlighted code
  const codeBlocks = document.querySelectorAll(".highlight pre");

  codeBlocks.forEach((codeBlock) => {
    // Create the copy button
    const button = document.createElement("button");
    button.className = "copy-button";

    // Add an SVG icon for the copy button
    // This is a simple SVG copy icon. You can replace it with any other icon SVG.
    button.innerHTML = `
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" viewBox="0 0 16 16">
                <path fill-rule="evenodd" d="M4 2a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V2Zm2-1a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V2a1 1 0 0 0-1-1H6Z"/>
                <path fill-rule="evenodd" d="M2 5a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1H2Zm-1-1a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2H2Z"/>
            </svg>
        `;

    // Append the button directly inside the <pre> element.
    // This allows its absolute positioning to be relative to the <pre> itself.
    codeBlock.appendChild(button);

    // Create a small message span for feedback (e.g., "Copied!")
    const message = document.createElement("span");
    message.className = "copy-message";
    // Append the message directly inside the <pre> element as well
    codeBlock.appendChild(message);

    // Add click event listener to the copy button
    button.addEventListener("click", function () {
      // Get the text content of the code block
      const textToCopy = codeBlock.textContent;

      // Create a temporary textarea to hold the text, select it, and copy
      // Using document.execCommand('copy') for broader compatibility in sandboxed environments
      const textArea = document.createElement("textarea");
      textArea.value = textToCopy;
      // Position the textarea off-screen to avoid visual disruption
      textArea.style.position = "fixed";
      textArea.style.left = "-9999px";
      document.body.appendChild(textArea);
      textArea.focus();
      textArea.select();

      try {
        // Attempt to copy the text
        document.execCommand("copy");
        message.textContent = "Copied!";
        message.style.opacity = "1";
        // Hide the message after a short delay
        setTimeout(() => {
          message.style.opacity = "0";
        }, 2000); // 2 seconds
      } catch (err) {
        console.error("Failed to copy text: ", err);
        message.textContent = "Failed to copy!";
        message.style.opacity = "1";
        setTimeout(() => {
          message.style.opacity = "0";
        }, 2000);
      } finally {
        // Clean up the temporary textarea
        document.body.removeChild(textArea);
      }
    });
  });
});
