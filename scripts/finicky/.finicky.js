module.exports = {
  defaultBrowser: "Google Chrome",
  rewrite: [],
  handlers: [
    {
      match: finicky.matchHostnames([
        "metabase.suzuri.jp",
        "pepabo.onelogin.com",
        "scrapbox.pepabo.com",
        "git.pepabo.com"
      ]),
      browser: {
        name: "Google Chrome",
        profile: "Default",
      },
    },
    {
      match: ["www.notion.so/pepabo/*"],
      browser: {
        name: "Google Chrome",
        profile: "Default",
      },
    },
    {
      match: finicky.matchHostnames([
        "www.amazon.co.jp",
        "twitter.com",
        "www.instagram.com",
        "www.facebook.com",
        "scrapbox.io",
        /hateblo.jp/,
        /(hatenablog|hatenadiary)\.(com|jp)/,
        "note.com",
        "github.com"
      ]),
      browser: {
        name: "Google Chrome",
        profile: "Profile 1",
      },
    },
    {
      match: finicky.matchHostnames([
        "zoom.us",
        "pepabo.zoom.us"
      ]),
      browser: "/Applications/zoom.us.app"
    },
  ]
};
