class SuggestedAddon {
  const SuggestedAddon(this.name, this.kind, this.url);

  final String name;
  final String kind;
  final String url;
}

const suggestedAddons = [
  SuggestedAddon('Banglaplex', 'Streams', 'https://banglaplex-94zf.onrender.com/manifest.json'),
  SuggestedAddon('The Pirate Bay+', 'Streams', 'https://thepiratebay-plus.strem.fun/manifest.json'),
  SuggestedAddon('Comet', 'Streams', 'https://comet.elfhosted.com/manifest.json'),
  SuggestedAddon('FenixFlix', 'Streams', 'https://fenixflix.fenixhub.online/manifest.json'),
  SuggestedAddon('SubDL', 'Subtitles', 'https://subdl.strem.top/manifest.json'),
];
