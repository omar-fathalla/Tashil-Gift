"use strict";

/**
 * Brand names the client knows (CampaignAiAssistantService.knownCompanySubBrands,
 * PromotionalRuleMatcher._brandRoots and the tenant competitor guards in
 * ai_receipt_service.dart). Used only to recognise a line that NAMES a brand
 * the campaign does not cover; it never puts a line into a campaign.
 * Words that are also everyday Arabic words (حلوة، المطبخ، الملكة، سيد …) are
 * left out so a generic line is not mistaken for another brand.
 */
const { norm } = require("./consuming_spend_ladder");

const COMPANY_BRANDS = [
  { company: ["ادكو", "adco"], brands: ["ديفا", "diva", "ديفاتول", "divatol", "فيبا", "feba", "ماكسيل ماجيك", "maxel magic",
    "فلفيتا", "velveta", "كلوريل", "clorel", "سبيد", "speed", "جلاسي", "glassy", "رابيدو", "rapido", "سوبر ماكس", "super max"] },
  { company: ["نستله", "نستلة", "nestle"], brands: ["كيت كات", "kitkat", "نسكافيه", "نسكافية", "nescafe", "سيريلاك", "cerelac",
    "اس 26", "s 26", "نسكويك", "nesquik", "ماجي", "maggi", "نيدو", "nido"] },
  { company: ["يونيليفر", "unilever"], brands: ["سيجنال", "signal", "كلوس اب", "كلوساب", "closeup", "ريكسونا", "rexona", "axe",
    "دوف", "dove", "لوكس", "lux", "صانسيلك", "صنسيلك", "sunsilk", "كلير", "clear", "تريزيمي", "tresemme", "لايف بوي", "لايفبوي",
    "lifebuoy", "كنور", "knorr", "ليبتون", "lipton", "فازلين", "vaseline"] },
  { company: ["ايديتا", "edita"], brands: ["مولتو", "molto", "هوهوز", "hohos", "توينكيز", "twinkies", "فريسكا", "freska",
    "بيك رولز", "بيك ستيكس", "ميميكس", "mimix", "اونيرو", "oniro"] },
  { company: ["بروكتر", "p g"], brands: ["اريال", "ariel", "تايد", "tide", "بونكس", "bonux", "داوني", "downy", "فيري", "fairy",
    "بامبرز", "pampers", "بانتين", "pantene", "هيد اند شولدرز", "head shoulders", "اولويز", "always", "جيليت", "gillette"] },
  { company: ["صافولا", "savola"], brands: ["عافيه", "afia", "هنادي", "hanadi", "مكرونتو", "macaronto"] },
  { company: ["فاين", "fine"], brands: ["فلافي", "fluffy", "فاين كير", "fine care"] },
  { company: ["المراعي", "almarai"], brands: ["بيتي", "beyti", "تروبيكانا", "tropicana"] },
  { company: ["دومتي", "domty"], brands: [] },
  { company: ["هاينز", "heinz"], brands: ["كرافت", "kraft"] },
  { company: ["شومان", "shoman", "shouman"], brands: ["الدره", "دره", "dorra", "durra", "سيد اوغلو", "seyidoglu"] },
  { company: [], brands: ["كلوركس", "clorox", "قودي", "goody", "هارفست", "harvest", "فاين فودز", "امريكانا", "americana",
    "جهينه", "juhayna", "لمار", "lamar", "الضحي", "كادبوري", "cadbury", "اوريو", "oreo"] },
];

const GROUPS = COMPANY_BRANDS.map((group) => ({
  company: group.company.map(norm).filter(Boolean),
  brands: group.company.concat(group.brands).map(norm).filter(Boolean),
}));

function hasWords(text, token) {
  return ` ${text} `.includes(` ${token} `);
}

/**
 * Whether the line name contains a known brand that none of the campaign's
 * scope texts (rule brands, trigger, catalog names, required products) covers.
 * A company name in the scope covers all of that company's brands.
 */
function namesBrandOutsideCampaign(lineName, scopeTexts) {
  const name = norm(lineName);
  if (!name) return false;
  const scope = (scopeTexts || []).map(norm).filter(Boolean);
  const covered = (token) => scope.some((text) => hasWords(text, token));
  for (const group of GROUPS) {
    const companyCovered = group.company.some(covered);
    for (const token of group.brands) {
      if (hasWords(name, token) && !companyCovered && !covered(token)) return true;
    }
  }
  return false;
}

module.exports = { namesBrandOutsideCampaign };
