angular.module("beamng.apps")
.directive("tyreWearThermals", ["CanvasShortcuts", function (CanvasShortcuts) {
    return {
        template: '<canvas width="220"></canvas>',
        replace: true,
        restrict: "EA",
        link: function (scope, element, attrs) {
            var streamsList = ["TyreWearThermals"];
            StreamsManager.add(streamsList);
            scope.$on("$destroy", function() {
                StreamsManager.remove(streamsList);
            });
            var c = element[0], ctx = c.getContext("2d");
            scope.$on('app:resized', function (event, data) {
                c.width = data.width
                c.height = data.height
            });
            scope.$on("streamsUpdate", function (event, streams) {
                // From: https://stackoverflow.com/a/3368118
                function roundRect(
                    ctx,
                    x,
                    y,
                    width,
                    height,
                    radius = 5,
                    fill = false,
                    stroke = true
                ) {
                    if (typeof radius === 'number') {
                        radius = {tl: radius, tr: radius, br: radius, bl: radius};
                    } else {
                        radius = {...{tl: 0, tr: 0, br: 0, bl: 0}, ...radius};
                    }
                    ctx.beginPath();
                    ctx.moveTo(x + radius.tl, y);
                    ctx.lineTo(x + width - radius.tr, y);
                    ctx.quadraticCurveTo(x + width, y, x + width, y + radius.tr);
                    ctx.lineTo(x + width, y + height - radius.br);
                    ctx.quadraticCurveTo(x + width, y + height, x + width - radius.br, y + height);
                    ctx.lineTo(x + radius.bl, y + height);
                    ctx.quadraticCurveTo(x, y + height, x, y + height - radius.bl);
                    ctx.lineTo(x, y + radius.tl);
                    ctx.quadraticCurveTo(x, y, x + radius.tl, y);
                    ctx.closePath();
                    if (fill) {
                        ctx.fill();
                    }
                    if (stroke) {
                        ctx.stroke();
                    }
                }

                function drawWheelData(name, contact_material, tread_coef, avg_temp, temps, working_temp, condition, load_bias, brake_temp, brake_working_temp) {
                    ctx.textAlign = 'center';

                    var right = 0;
                    var back = 0;

                    if (name == "RR" || name == "RL") {
                        back = 1;
                    }

                    if (name == "FR" || name == "RR") {
                        right = 1;
                    }

                    var w = c.width / 3.5;
                    var h = c.height / 3.5;
                    var x = w * 0.5 + ((w * 1.5) * right);
                    var y = (h * 0.5 + ((h * 1.5) * back)) + h * 0.1;
                    var cx = x + w * 0.5;
                    var cy = y + h * 0.5;

                    h = h * 0.8;

                    // Draw info text
                    ctx.fillStyle = "#ffffffff";
                    ctx.font = 'bold 18pt "Lucida Console", Monaco, monospace';
                    // ctx.fillText("" + Math.ceil(condition) + "%", cx, y - 8);
                    ctx.fillText("" + Math.ceil(temps[3]) + " C", cx, y - 8);

                    var t = condition / 100;

                    var lowHue = 0;
                    var highHue = 248;

                    for (let i = 0; i < 3; i++) {
                        var tempT = 1.0 - Math.min(Math.max(temps[i] / working_temp - 0.5, 0), 1);
                        var hue = lowHue + (highHue - lowHue) * tempT;

                        var crad = 8.0;
                        var radius = {tl: 0, tr: 0, br: 0, bl: 0};
                        if (i == 0) {
                            radius = {tl: crad, tr: 0, br: 0, bl: crad};
                        } else if (i == 2) {
                            radius = {tl: 0, tr: crad, br: crad, bl: 0};
                        }

                        ctx.lineWidth = "0";
                        ctx.fillStyle = "rgba(0,0,0,0.45)";
                        ctx.beginPath();
                        ctx.rect(x + (w / 3.0 * i) + 2, y + 1, w / 3.0 - 4, h - 2);
                        ctx.fill();
                        if (t > 0.1) {
                            var ft = 1.0 - t;
                            ctx.fillStyle = "hsla(" + hue + ",82%,56%,1)";
                            ctx.beginPath();
                            ctx.rect(x + (w / 3.0 * i) + 2, y+h*ft + 1, w / 3.0 - 4, h - h*ft - 2);
                            ctx.fill();
                        }
                        ctx.lineWidth = "3";
                        ctx.strokeStyle = "rgba(0,0,0,1)";
                        roundRect(ctx, x + (w / 3.0 * i) + 1, y, w / 3.0 - 2, h, radius, false);

                        // Info text
                        ctx.fillStyle = "#ffffffff";
                        var font_size = Math.max(Math.min(w / 20.0 * 3.0, 16.0), 4.0);
                        ctx.font = 'bold ' + font_size + 'pt "Lucida Console", Monaco, monospace';
                        ctx.fillText("" + Math.floor(temps[i]), x + (w / 3.0 * i) + 2 + (w / 3.0 - 8) / 2.0, y + h + 22);

                        // Load bias
                        ctx.fillStyle = "rgba(255,50,50,0.85)";
                        ctx.beginPath();
                        ctx.moveTo(x + w * 0.5 + w * (load_bias * 0.5), y - 2);
                        ctx.lineTo(x + w * 0.5 + w * (load_bias * 0.5) - 6, y - 8);
                        ctx.lineTo(x + w * 0.5 + w * (load_bias * 0.5) + 6, y - 8);
                        ctx.fill();

                        ctx.beginPath();
                        ctx.moveTo(x + w * 0.5 + w * (load_bias * 0.5), y + h + 2);
                        ctx.lineTo(x + w * 0.5 + w * (load_bias * 0.5) - 6, y + h + 8);
                        ctx.lineTo(x + w * 0.5 + w * (load_bias * 0.5) + 6, y + h + 8);
                        ctx.fill();
                    }

                    // Draw brakes
                    // var brakeTempT = 1.0 - Math.min(Math.max(brake_temp / brake_working_temp - 0.5, 0), 1);
                    // var brakeHue = lowHue + (highHue - lowHue) * brakeTempT;
                    // ctx.fillStyle = "hsla(" + hue + ",82%,56%,1)";
                    // roundRect(ctx, cx - w / 24.0 - w / 1.75 * (right * 2.0 - 1.0), y + h * 0.2, w / 12.0, h * 0.6, 3.0, true);
                        // Draw core temp
                    var coreTempT = 1.0 - Math.min(Math.max(temps[3] / working_temp - 0.5, 0), 1);
                    var coreHue = lowHue + (highHue - lowHue) * coreTempT;
                    ctx.fillStyle = "hsla(" + coreHue + ",82%,56%,1)";
                    roundRect(ctx, cx - w / 24.0 - w / 1.75 * (right * 2.0 - 1.0), y + h * 0.2, w / 12.0, h * 0.6, 3.0, true);
                }

                var dataStream = streams.TyreWearThermals;
                ctx.setTransform(1, 0, 0, 1, 0, 0); // No scaling, no skewing, no translation
                ctx.clearRect(0, 0, c.width, c.height);

                ctx.textAlign = 'center';

                for (let i = 0; i < dataStream.data.length; i++) {
                    drawWheelData(
                        dataStream.data[i].name,
                        dataStream.data[i].contact_material,
                        dataStream.data[i].tread_coef,
                        dataStream.data[i].avg_temp,
                        dataStream.data[i].temp,
                        dataStream.data[i].working_temp,
                        dataStream.data[i].condition,
                        dataStream.data[i].load_bias,
                        dataStream.data[i].brake_temp,
                        dataStream.data[i].brake_working_temp,
                    );
                }
            });
        }
    }
}])
