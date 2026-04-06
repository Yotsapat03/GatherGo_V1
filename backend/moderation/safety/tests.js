const TEST_CASES = [
  {
    id: "direct_hate_speech",
    message: "i hate all black people",
    expectedAction: "block",
    expectedCategories: ["protected_class_attack"],
  },
  {
    id: "obfuscated_hate_speech",
    message: "n i g g a get out",
    expectedAction: "block",
    expectedCategories: ["hate_speech"],
  },
  {
    id: "nationality_slur_controlled",
    message: "pajeet",
    expectedAction: "block",
    expectedCategories: ["hate_speech"],
  },
  {
    id: "nationality_slur_jap",
    message: "jap",
    expectedAction: "block",
    expectedCategories: ["hate_speech"],
  },
  {
    id: "quoted_evidence",
    message: 'user reported: "i hate all muslims"',
    expectedAction: "review",
    expectedCategories: ["protected_class_attack"],
  },
  {
    id: "moderation_discussion",
    message: "this moderation example discusses anti-gay abuse patterns",
    expectedAction: "review",
    expectedCategories: ["protected_class_attack"],
  },
  {
    id: "non_hateful_profanity",
    message: "this run was fucking hard",
    expectedAction: "allow",
    expectedCategories: ["allow"],
  },
  {
    id: "sexual_insult_without_protected_class",
    message: "that creep is a pervert",
    expectedAction: "review",
    expectedCategories: ["harassment"],
  },
  {
    id: "targeted_body_shaming",
    message: "you are so fat and ugly",
    expectedAction: "review",
    expectedCategories: ["targeted_abuse"],
  },
  {
    id: "body_trait_harassment",
    message: "look at your ugly face",
    expectedAction: "review",
    expectedCategories: ["harassment"],
  },
  {
    id: "nationality_attack",
    message: "those chinese people are disgusting",
    expectedAction: "block",
    expectedCategories: ["protected_class_attack"],
  },
  {
    id: "xenophobic_country_stereotype",
    message: "your country eat meaw",
    expectedAction: "block",
    expectedCategories: ["protected_class_attack"],
  },
  {
    id: "transphobic_country_stereotype",
    message: "ladyboy country",
    expectedAction: "block",
    expectedCategories: ["hate_speech"],
  },
  {
    id: "religion_attack",
    message: "all muslims should be banned",
    expectedAction: "block",
    expectedCategories: ["dehumanization"],
  },
  {
    id: "gender_attack",
    message: "women are trash",
    expectedAction: "block",
    expectedCategories: ["protected_class_attack"],
  },
  {
    id: "orientation_attack",
    message: "gay people do not belong here",
    expectedAction: "block",
    expectedCategories: ["dehumanization"],
  },
  {
    id: "disability_attack",
    message: "disabled people are worthless",
    expectedAction: "block",
    expectedCategories: ["protected_class_attack"],
  },
  {
    id: "threat_of_violence",
    message: "we should kill those jews",
    expectedAction: "block",
    expectedCategories: ["threat"],
  },
  {
    id: "false_positive_history",
    message: "the museum exhibit explains racist propaganda in history",
    expectedAction: "allow",
    expectedCategories: ["allow"],
  },
  {
    id: "false_positive_body_discussion",
    message: "the coach discussed body weight and running posture",
    expectedAction: "allow",
    expectedCategories: ["allow"],
  },
];

module.exports = {
  TEST_CASES,
};
