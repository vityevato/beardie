<ul>
{% for release in site.github.releases %}
    {% unless release.draft %}
        {% unless release.prerelease and page.release_only %}
            <li>
                <h1>{{ release.name }}</h1>
                <div>{{ release.body}}</div>
            </li>
        {% endunless %}
    {% endunless %}
{% endfor %}
</ul>
