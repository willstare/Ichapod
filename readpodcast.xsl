<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:variable name="channeltitle"><xsl:value-of select="/rss/channel/title"/></xsl:variable>
<xsl:template match="/">
<xsl:for-each select="rss/channel/item">
<xsl:copy-of select="$channeltitle" />---<xsl:value-of select="pubDate"/>---<xsl:value-of select="title"/>---<xsl:value-of select="enclosure/@url"/><xsl:text>&#xa;</xsl:text>
</xsl:for-each>
</xsl:template>
</xsl:stylesheet> 