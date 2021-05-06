<ul class="releases">
{% for release in site.github.releases limit:5 %}
    {% unless release.draft %}
        {% unless release.prerelease and include.release_only %}
            <li class="release">
                <h1>{{ release.name }}</h1>
                <div>{{ release.body | markdownify }}</div>
            </li>
        {% endunless %}
    {% endunless %}
{% endfor %}
</ul>
