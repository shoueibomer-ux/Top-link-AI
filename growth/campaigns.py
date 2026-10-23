"""Edmonton's seasonal campaigns: what growth.jobs reminds past clients about,
and when. Each one is tied to a launched catalog service (a campaign whose
service isn't launched is skipped) and runs in the months listed, in
Edmonton time.

`audience` is the services whose past clients "may need" this one: someone
who had their furnace looked at is the obvious audience for a furnace check,
and someone who had a deck built may well want it stained. The campaign's
own service is always part of its audience.

Copy rules as for the website: only what Tabmatch does, no prices or
discounts, nothing urgent-sounding. The push text stays short (it shows on a
lock screen); the email says why the person is getting it.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class Campaign:
    slug: str
    service: str
    months: tuple[int, ...]
    audience: tuple[str, ...]
    push_title: str
    push_body: str
    email_subject: str
    email_body: str

    def reaches(self, service_slug: str) -> bool:
        return service_slug == self.service or service_slug in self.audience


CAMPAIGNS = [
    Campaign(
        slug="sump-pump-spring",
        service="plumbing",
        months=(3, 4),
        audience=("plumbing",),
        push_title="Ready for the spring melt?",
        push_body="Have a plumber test your sump pump and backwater valve before the snow melts.",
        email_subject="Is your sump pump ready for the spring melt?",
        email_body=(
            "Edmonton's spring melt is when sump pumps and backwater valves do their hardest work. "
            "A quick test by a plumber now is a lot cheaper than a wet basement later."
        ),
    ),
    Campaign(
        slug="ac-check",
        service="hvac",
        months=(4, 5),
        audience=("hvac", "electrical"),
        push_title="Air conditioning check",
        push_body="Get your AC serviced before the first hot week of summer.",
        email_subject="Get your air conditioning checked before summer",
        email_body=(
            "The first hot week of an Edmonton summer is when every AC technician gets busy. "
            "A spring service cleans the coils, checks the refrigerant and makes sure it starts when you need it."
        ),
    ),
    Campaign(
        slug="exterior-painting",
        service="painting",
        months=(5, 6),
        audience=("painting", "carpentry", "construction-finishing"),
        push_title="Exterior painting season",
        push_body="Edmonton's painting season is short. Book your exterior painter early.",
        email_subject="Exterior painting season has started",
        email_body=(
            "Edmonton's exterior painting window runs from late May to mid-September, while it stays warm and dry. "
            "Painters book up quickly, so now is the time to ask about siding, trim, decks or fences."
        ),
    ),
    Campaign(
        slug="deck-and-fence",
        service="carpentry",
        months=(5, 6),
        audience=("carpentry", "painting", "metalwork-aluminum"),
        push_title="Deck and fence season",
        push_body="The ground has thawed: time for deck and fence repairs.",
        email_subject="Time to fix up the deck and fence",
        email_body=(
            "Once the ground has thawed, carpenters can set new posts and repair or rebuild decks, stairs and fences "
            "before summer gets going."
        ),
    ),
    Campaign(
        slug="furnace-check",
        service="hvac",
        months=(9, 10),
        audience=("hvac", "plumbing"),
        push_title="Furnace check before winter",
        push_body="Book a furnace tune-up before the cold arrives.",
        email_subject="Book your furnace check before winter",
        email_body=(
            "Edmonton furnaces run from October to April. A fall tune-up checks the burners, filter, venting and "
            "safety controls, so the first cold night isn't when you find a problem."
        ),
    ),
    Campaign(
        slug="window-seals",
        service="glass-mirrors",
        months=(9, 10),
        audience=("glass-mirrors", "carpentry", "construction-finishing"),
        push_title="Foggy windows?",
        push_body="Replace failed window seals before the frost sets in.",
        email_subject="Replace foggy or cracked windows before winter",
        email_body=(
            "Fog between the panes means a window's seal has failed, and it will frost over all winter. "
            "A glass specialist can often replace just the sealed unit in the existing frame."
        ),
    ),
    Campaign(
        slug="winterize-outdoor-taps",
        service="plumbing",
        months=(10,),
        audience=("plumbing",),
        push_title="Winterize your outdoor taps",
        push_body="Shut off and drain outdoor taps before the first hard frost.",
        email_subject="Winterize your outdoor taps before the frost",
        email_body=(
            "A frozen outdoor tap can split the pipe inside the wall. If your hose bibs don't have a shut-off you can "
            "reach, or one is already dripping, a plumber can fix it before the first hard frost."
        ),
    ),
    Campaign(
        slug="holiday-lighting",
        service="electrical",
        months=(11,),
        audience=("electrical",),
        push_title="Outdoor outlets for the holidays",
        push_body="Add or fix outdoor outlets before you hang the lights.",
        email_subject="Outdoor outlets and lighting for the holidays",
        email_body=(
            "If your holiday lights trip a breaker or run on extension cords across the lawn, an electrician can add "
            "GFCI-protected outdoor outlets or a timer circuit."
        ),
    ),
]

CAMPAIGN_BY_SLUG = {c.slug: c for c in CAMPAIGNS}


def active_campaigns(month: int, launched: set[str]) -> list[Campaign]:
    return [c for c in CAMPAIGNS if month in c.months and c.service in launched]
